// lenny#178: the provider's usage survives each real dartantic backend's
// stream mapping, not only the swift-infer path.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:leonard_agent/src/observation/diff_models.dart';
import 'package:leonard_agent/src/observation/models.dart';
import 'package:leonard_agent/src/provider/action_schema.dart';
import 'package:leonard_agent/src/provider/backend/dartantic_model_provider.dart';
import 'package:leonard_agent/src/provider/backend/model_backend.dart';
import 'package:leonard_agent/src/provider/types.dart';
import 'package:test/test.dart';

class _SseClient extends http.BaseClient {
  _SseClient(this.events);

  /// `(event name or null, data)` pairs, written as one SSE frame each.
  final List<(String?, Map<String, dynamic>)> events;
  String? body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) body = request.body;
    final sb = StringBuffer();
    for (final (name, data) in events) {
      if (name != null) sb.write('event: $name\n');
      sb.write('data: ${jsonEncode(data)}\n\n');
    }
    sb.write('data: [DONE]\n\n');
    return http.StreamedResponse(
      Stream.value(utf8.encode(sb.toString())),
      200,
      headers: const {'content-type': 'text/event-stream'},
    );
  }
}

const _caps = ModelCapabilities(
  vision: false,
  preserveThinking: false,
  maxContext: 128000,
  supportsToolUse: true,
);

const _tap = ToolDescriptor(
  name: 'core.tap',
  description: 'tap a node',
  inputSchema: {
    'type': 'object',
    'properties': {
      'nodeId': {'type': 'integer'},
    },
    'required': ['nodeId'],
    'additionalProperties': false,
  },
);

ConversationSnapshot _snapshot() => ConversationSnapshot(
  systemMessage: 'you are an agent',
  turns: [
    UserTurn(observation: Observation.empty(), diff: ObservationDiff.empty()),
  ],
  tools: const [_tap],
);

void main() {
  test(
    'anthropic: input from message_start, output from message_delta',
    () async {
      final client = _SseClient([
        (
          'message_start',
          {
            'type': 'message_start',
            'message': {
              'id': 'msg_a',
              'type': 'message',
              'role': 'assistant',
              'model': 'claude-sonnet-4-6',
              'content': <Object>[],
              'stop_reason': null,
              'stop_sequence': null,
              'usage': {'input_tokens': 3100, 'output_tokens': 1},
            },
          },
        ),
        (
          'content_block_start',
          {
            'type': 'content_block_start',
            'index': 0,
            'content_block': {
              'type': 'tool_use',
              'id': 'tu1',
              'name': 'core_tap',
              'input': <String, dynamic>{},
            },
          },
        ),
        (
          'content_block_delta',
          {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {
              'type': 'input_json_delta',
              'partial_json': '{"nodeId":3}',
            },
          },
        ),
        ('content_block_stop', {'type': 'content_block_stop', 'index': 0}),
        (
          'message_delta',
          {
            'type': 'message_delta',
            'delta': {'stop_reason': 'tool_use', 'stop_sequence': null},
            'usage': {'output_tokens': 64},
          },
        ),
        ('message_stop', {'type': 'message_stop'}),
      ]);
      final provider = DartanticModelProvider(
        backend: const AnthropicBackend(apiKey: 'k'),
        model: 'claude-sonnet-4-6',
        capabilities: _caps,
        client: client,
      );

      final decision = await provider.decide(
        _snapshot(),
        ActionSchema.fromToolList(const [_tap]),
      );

      expect(decision.action.args, {'nodeId': 3});
      expect(decision.usage?.provider, 'anthropic');
      expect(decision.usage?.inputTokens, 3100);
      expect(decision.usage?.outputTokens, 64);
      provider.dispose();
    },
  );

  test(
    'openai: asks for stream usage and reads the final usage chunk',
    () async {
      Map<String, dynamic> chunk(
        Map<String, dynamic> delta, {
        String? finish,
      }) => {
        'id': 'chatcmpl-1',
        'object': 'chat.completion.chunk',
        'created': 1,
        'model': 'gpt-5',
        'choices': [
          {'index': 0, 'delta': delta, 'finish_reason': finish},
        ],
      };
      final client = _SseClient([
        (
          null,
          chunk({
            'role': 'assistant',
            'tool_calls': [
              {
                'index': 0,
                'id': 'call_1',
                'type': 'function',
                'function': {'name': 'core_tap', 'arguments': ''},
              },
            ],
          }),
        ),
        (
          null,
          chunk({
            'tool_calls': [
              {
                'index': 0,
                'function': {'arguments': '{"nodeId":5}'},
              },
            ],
          }),
        ),
        (null, chunk(<String, dynamic>{}, finish: 'tool_calls')),
        (
          null,
          {
            'id': 'chatcmpl-1',
            'object': 'chat.completion.chunk',
            'created': 1,
            'model': 'gpt-5',
            'choices': <Object>[],
            'usage': {
              'prompt_tokens': 2048,
              'completion_tokens': 210,
              'total_tokens': 2258,
            },
          },
        ),
      ]);
      // dartantic's OpenAI provider takes no injected client, so serve the
      // canned stream from loopback instead of letting it reach the network.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      String? body;
      server.listen((HttpRequest req) async {
        body = await utf8.decoder.bind(req).join();
        final canned = await client.send(http.Request('POST', req.uri));
        req.response.headers.contentType = ContentType('text', 'event-stream');
        await req.response.addStream(canned.stream);
        await req.response.close();
      });
      final provider = DartanticModelProvider(
        backend: OpenAIBackend(
          apiKey: 'k',
          baseUrl: Uri.parse('http://127.0.0.1:${server.port}/v1'),
        ),
        model: 'gpt-5',
        capabilities: _caps,
      );

      final decision = await provider.decide(
        _snapshot(),
        ActionSchema.fromToolList(const [_tap]),
      );

      final request = jsonDecode(body!) as Map<String, dynamic>;
      expect(request['stream_options'], {'include_usage': true});
      expect(decision.action.args, {'nodeId': 5});
      expect(decision.usage?.provider, 'openai');
      expect(decision.usage?.inputTokens, 2048);
      expect(decision.usage?.outputTokens, 210);
      provider.dispose();
    },
  );
}
