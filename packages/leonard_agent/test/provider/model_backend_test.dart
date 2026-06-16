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
  });
}
