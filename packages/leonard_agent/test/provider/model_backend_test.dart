import 'dart:convert';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:http/http.dart' as http;
import 'package:leonard_agent/src/provider/backend/model_backend.dart';
import 'package:leonard_agent/src/provider/swift_infer/swift_infer_chat_model.dart';
import 'package:test/test.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this.events);

  final List<Map<String, dynamic>> events;
  http.BaseRequest? captured;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    captured = request;
    final sb = StringBuffer();
    for (final e in events) {
      sb.write('data: ${jsonEncode(e)}\n\n');
    }
    sb.write('data: [DONE]\n\n');
    return http.StreamedResponse(Stream.value(utf8.encode(sb.toString())), 200);
  }
}

void main() {
  group('buildBackendChatModel', () {
    test('swift-infer spec builds a SwiftInferChatModel', () {
      final m = buildBackendChatModel(
        SwiftInferBackend(
          baseUrl: Uri.parse('http://localhost:8080'),
          bearerToken: 'x',
        ),
        model: 'qwen',
      );
      expect(m, isA<SwiftInferChatModel>());
    });

    test('anthropic spec builds a stock AnthropicChatModel', () {
      final m = buildBackendChatModel(
        const AnthropicBackend(apiKey: 'k'),
        model: 'claude-sonnet-4-0',
      );
      expect(m, isA<AnthropicChatModel>());
    });

    test('openai spec builds a stock OpenAIChatModel', () {
      final m = buildBackendChatModel(
        const OpenAIBackend(apiKey: 'k'),
        model: 'gpt-4o',
      );
      expect(m, isA<OpenAIChatModel>());
    });

    test(
      'swift-infer factory path streams through the supplied client',
      () async {
        final client = _FakeClient([
          {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'text_delta', 'text': 'hi'},
          },
        ]);
        final m = buildBackendChatModel(
          SwiftInferBackend(
            baseUrl: Uri.parse('http://localhost:8080'),
            bearerToken: 'tok',
          ),
          model: 'qwen',
          client: client,
        );
        final parts = <Part>[];
        await for (final r in m.sendStream([ChatMessage.user('go')])) {
          parts.addAll(r.output.parts);
        }
        m.dispose();

        expect(parts.whereType<TextPart>().map((p) => p.text).join(), 'hi');
        // the factory wired the bearer token and the swift-infer endpoint.
        expect(
          client.captured!.url.toString(),
          'http://localhost:8080/v1/messages',
        );
        expect(client.captured!.headers['authorization'], 'Bearer tok');
      },
    );

    test('anthropic default keeps thinking on WITHOUT a forcing tool_choice '
        '(Anthropic rejects thinking + forced tool_choice)', () async {
      final client = _FakeClient([
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'text_delta', 'text': 'hi'},
        },
      ]);
      // Defaults: enableThinking == true. With a tool offered, dartantic
      // emits tool_choice — and Anthropic 400s ("Thinking may not be enabled
      // when tool_choice forces tool use") if that choice forces a tool.
      final m = buildBackendChatModel(
        const AnthropicBackend(apiKey: 'k'),
        model: 'claude-sonnet-4-0',
        tools: [
          Tool(
            name: 'core_tap',
            description: 'tap a node',
            inputSchema: Schema.fromMap(const <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{},
            }),
            onCall: (_) async => null,
          ),
        ],
        client: client,
      );
      await for (final _ in m.sendStream([ChatMessage.user('go')])) {}
      m.dispose();

      final body =
          jsonDecode((client.captured! as http.Request).body)
              as Map<String, dynamic>;
      // Thinking is on...
      expect(
        body['thinking'],
        isNotNull,
        reason: 'thinking should be enabled by default',
      );
      // ...so the tool_choice must not force a tool (auto, or omitted)...
      final toolChoice = body['tool_choice'] as Map<String, dynamic>?;
      final tcType = toolChoice?['type'];
      expect(
        tcType,
        isNot(anyOf('any', 'tool')),
        reason:
            'forced tool_choice ($tcType) is incompatible with thinking — '
            'Anthropic rejects the request',
      );
      // ...and temperature must be 1 (or omitted): Anthropic rejects any
      // other temperature when thinking is enabled.
      final temperature = body['temperature'];
      expect(
        temperature == null || temperature == 1,
        isTrue,
        reason:
            'temperature ($temperature) must be 1 or unset when thinking is '
            'enabled — Anthropic rejects the request otherwise',
      );
    });
  });
}
