import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:leonard_agent/src/provider/openai/openai_parse.dart';
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

ConversationSnapshot _prompt({Observation? observation}) {
  final builder = ConversationBuilder(
    systemMessage: 'sys',
    tools: <ToolDescriptor>[_tap()],
  );
  builder.appendUserTurn(
    observation ?? Observation.empty(),
    ObservationDiff.empty(),
  );
  return builder.snapshot();
}

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
    final obs = Observation.fromJson(<String, dynamic>{
      'screenshot_png_b64': img.base64Png,
    });

    await _provider(mock).decide(_prompt(observation: obs), s);

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

  test('unknown tool name → SchemaRejection (unknown tool, available list)',
      () {
    const navigateTool = ToolDescriptor(
      name: 'router.navigate',
      description: 'navigate',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'route_name': <String, dynamic>{'type': 'string'},
        },
        'required': <String>['route_name'],
        'additionalProperties': false,
      },
    );
    final body = <String, dynamic>{
      'choices': <Map<String, dynamic>>[
        <String, dynamic>{
          'message': <String, dynamic>{
            'role': 'assistant',
            'tool_calls': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'call_1',
                'type': 'function',
                'function': <String, dynamic>{
                  'name': 'navigate',
                  'arguments': '{"route_name":"settings"}',
                },
              },
            ],
          },
        },
      ],
    };
    final tools = <ToolDescriptor>[_tap(), navigateTool];
    expect(
      () => parseOpenAiResponse(
        body,
        schema: ActionSchema.fromToolList(tools),
        tools: tools,
      ),
      throwsA(
        isA<SchemaRejection>()
            .having(
              (SchemaRejection e) => e.validationError,
              'validationError',
              'model emitted unknown tool: navigate; available: [core_tap, router_navigate]',
            )
            .having(
              (SchemaRejection e) => jsonDecode(e.rawOutput),
              'rawOutput',
              <String, Object?>{
                'name': 'navigate',
                'arguments': <String, Object?>{'route_name': 'settings'},
              },
            ),
      ),
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

  test('2-turn snapshot: role:tool message follows assistant tool_calls; ids match', () async {
    Map<String, dynamic>? sent;
    final mock = MockClient((req) async {
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(jsonEncode(_resp('core.tap', '{"node_id":7}')), 200);
    });
    final builder = ConversationBuilder(
      systemMessage: 'sys',
      tools: <ToolDescriptor>[_tap()],
    );
    builder.appendUserTurn(Observation.empty(), ObservationDiff.empty());
    builder.appendAssistantTurn('', (tool: 'core.tap', args: <String, dynamic>{'node_id': 1}));
    builder.appendUserTurn(Observation.empty(), ObservationDiff.empty());
    final s = ActionSchema.fromToolList(<ToolDescriptor>[_tap()]);
    await _provider(mock).decide(builder.snapshot(), s);
    final msgs = sent!['messages'] as List;
    final assistantMsg = msgs.firstWhere(
      (m) => (m as Map)['role'] == 'assistant',
    ) as Map;
    final callId =
        ((assistantMsg['tool_calls'] as List).first as Map)['id'] as String;
    expect(callId, isNot('call_carry'));
    final toolMsg = msgs.firstWhere(
      (m) => (m as Map)['role'] == 'tool',
    ) as Map;
    expect(toolMsg['tool_call_id'], callId);
  });
}
