import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:exploration_agent/exploration_agent.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

ToolDescriptor _tap() => const ToolDescriptor(
      name: 'core.tap',
      description: 'tap',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'node_id': <String, dynamic>{'type': 'integer'},
        },
        'required': <String>['node_id'],
        'additionalProperties': false,
      },
    );

PromptPayload _prompt({Map<String, dynamic>? user}) => PromptPayload(
      systemMessage: 'sys',
      userMessages: <Map<String, dynamic>>[
        user ?? <String, dynamic>{'text': 'hi'},
      ],
      tools: <ToolDescriptor>[_tap()],
    );

Map<String, dynamic> _resp(String name, String args) => <String, dynamic>{
      'choices': <Map<String, dynamic>>[
        <String, dynamic>{
          'message': <String, dynamic>{
            'role': 'assistant',
            'tool_calls': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'c1',
                'type': 'function',
                'function': <String, dynamic>{
                  'name': name,
                  'arguments': args,
                },
              },
            ],
          },
        },
      ],
    };

OpenAiModelProvider _provider(http.Client client, {String model = 'gpt-5'}) =>
    OpenAiModelProvider(modelId: model, apiKey: 'k', client: client);

void main() {
  test('happy path: tool_calls parsed; frontier defaults present', () async {
    Map<String, dynamic>? captured;
    final mock = MockClient((req) async {
      captured = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(jsonEncode(_resp('core.tap', '{"node_id":42}')), 200);
    });
    final s = ActionSchema.fromToolList(<ToolDescriptor>[_tap()]);

    final d = await _provider(mock).decide(_prompt(), s);

    expect(d.action.tool, 'core.tap');
    expect(d.action.args['node_id'], 42);
    expect(captured, isNotNull);
    expect(captured!['temperature'], isA<num>());
    expect(captured!['max_completion_tokens'], isA<int>());
    expect((captured!['max_completion_tokens'] as int) > 0, isTrue);
    expect(captured!['tool_choice'], 'required');
    final tools = captured!['tools'] as List;
    expect(((tools.first as Map)['function'] as Map)['name'], 'core.tap');
  });

  test('vision: screenshot becomes image_url content part', () async {
    Map<String, dynamic>? captured;
    final mock = MockClient((req) async {
      captured = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(jsonEncode(_resp('core.tap', '{"node_id":1}')), 200);
    });
    final s = ActionSchema.fromToolList(<ToolDescriptor>[_tap()]);
    final img = VisionImage.fromPngBytes(Uint8List.fromList(<int>[0, 0, 0, 1]));

    await _provider(mock).decide(
      _prompt(user: <String, dynamic>{'text': 's', 'screenshot': img}),
      s,
    );

    final messages = captured!['messages'] as List;
    final userMsg = messages.firstWhere(
      (m) => (m as Map)['role'] == 'user',
    ) as Map;
    final parts = userMsg['content'] as List;
    final imagePart = parts.firstWhere(
      (p) => (p as Map)['type'] == 'image_url',
    ) as Map;
    final urlMap = imagePart['image_url'] as Map;
    expect(urlMap['url'], startsWith('data:image/png;base64,'));
    expect(urlMap['url'], contains(img.base64Png));
  });

  test('schema rejection retries once then succeeds', () async {
    var calls = 0;
    final mock = MockClient((req) async {
      calls += 1;
      if (calls == 1) {
        // First call: empty args fail required[node_id] validation.
        return http.Response(jsonEncode(_resp('core.tap', '{}')), 200);
      }
      // Second call: valid args.
      return http.Response(jsonEncode(_resp('core.tap', '{"node_id":7}')), 200);
    });
    final s = ActionSchema.fromToolList(<ToolDescriptor>[_tap()]);

    final d = await _provider(mock).decide(_prompt(), s);

    expect(calls, 2);
    expect(d.action.args['node_id'], 7);
  });

  test('second rejection propagates SchemaRejection', () async {
    final mock = MockClient((req) async =>
        http.Response(jsonEncode(_resp('core.tap', '{}')), 200));
    final s = ActionSchema.fromToolList(<ToolDescriptor>[_tap()]);

    await expectLater(
      _provider(mock).decide(_prompt(), s),
      throwsA(isA<SchemaRejection>()),
    );
  });

  test('capabilities reports vision per model', () {
    final mock = MockClient((_) async => http.Response('', 200));
    final caps = _provider(mock).capabilities;
    expect(caps.vision, isTrue);
    expect(caps.preserveThinking, isFalse);
    expect(caps.supportsToolUse, isTrue);
    expect(caps.maxContext, greaterThan(0));

    final caps2 = _provider(mock, model: 'gpt-5-mini').capabilities;
    expect(caps2.vision, isTrue);
    expect(caps2.supportsToolUse, isTrue);
  });

  test('streaming surfaces ThinkingDelta events', () async {
    const sse = 'data: {"choices":[{"delta":{"content":"hi"}}]}\n\n'
        'data: {"choices":[{"delta":{"content":"!"}}]}\n\n'
        'data: [DONE]\n\n';
    final mock = MockClient.streaming((req, body) async {
      final stream = Stream<List<int>>.value(utf8.encode(sse));
      return http.StreamedResponse(stream, 200);
    });
    final provider = _provider(mock);
    final s = ActionSchema.fromToolList(<ToolDescriptor>[_tap()]);

    final collected = <ThinkingDelta>[];
    final sub = provider.thinking().listen(collected.add);

    await provider.streamThinking(_prompt(), s);
    // Yield so any final event posted just before return is delivered.
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    unawaited(provider.close());

    final nonFinal = collected.where((d) => !d.isFinal).map((d) => d.text).toList();
    expect(nonFinal, <String>['hi', '!']);
    expect(collected.last.isFinal, isTrue);
  });
}
