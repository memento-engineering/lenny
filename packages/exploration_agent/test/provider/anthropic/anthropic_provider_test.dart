import 'dart:convert';
import 'dart:typed_data';

import 'package:exploration_agent/exploration_agent.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

ToolDescriptor _t(String n) => ToolDescriptor(
      name: n,
      description: n,
      inputSchema: const <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'node_id': <String, dynamic>{'type': 'integer'},
        },
        'required': <String>['node_id'],
        'additionalProperties': false,
      },
    );

PromptPayload _prompt({List<Map<String, dynamic>>? user}) => PromptPayload(
      systemMessage: 'sys',
      userMessages: user ??
          <Map<String, dynamic>>[
            <String, dynamic>{'type': 'text', 'text': 'hi'},
          ],
      tools: <ToolDescriptor>[_t('core.tap')],
    );

AnthropicModelProvider _p(MockClient m, {String model = 'claude-sonnet-4-6'}) =>
    AnthropicModelProvider(model: model, apiKey: 'k', client: m);

MockClient _ok(Map<String, dynamic> body) =>
    MockClient((req) async => http.Response(jsonEncode(body), 200));

void main() {
  test('happy path: tool_use → ModelDecision', () async {
    final m = _ok(<String, dynamic>{
      'content': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'tool_use',
          'name': 'core_tap',
          'input': <String, dynamic>{'node_id': 7},
        },
      ],
    });
    final s = ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]);
    final d = await _p(m).decide(_prompt(), s);
    expect(d.action.tool, 'core.tap');
    expect(d.action.args['node_id'], 7);
  });

  test('missing tool_use → SchemaRejection', () async {
    final m = _ok(<String, dynamic>{
      'content': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'text': 'no'},
      ],
    });
    final s = ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]);
    expect(
      () => _p(m).decide(_prompt(), s),
      throwsA(isA<SchemaRejection>().having(
        (e) => e.validationError,
        'err',
        contains('no tool_use block'),
      )),
    );
  });

  test('screenshot turn includes image block', () async {
    Map<String, dynamic>? captured;
    final m = MockClient((req) async {
      captured = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode(<String, dynamic>{
          'content': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'tool_use',
              'name': 'core_tap',
              'input': <String, dynamic>{'node_id': 1},
            },
          ],
        }),
        200,
      );
    });
    final s = ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]);
    final img = VisionImage.fromPngBytes(Uint8List.fromList(<int>[1, 2, 3]));
    await _p(m).decide(
      _prompt(user: <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'text': 'look'},
        img.toAnthropicBlock(),
      ]),
      s,
    );
    final messages = captured!['messages'] as List;
    final content = (messages[0] as Map)['content'] as List;
    final block = content.firstWhere(
      (b) => (b as Map)['type'] == 'image',
    ) as Map;
    final source = block['source'] as Map;
    expect(source['media_type'], 'image/png');
    expect(source['data'], isNotEmpty);
  });

  test('ActionSchema rejection escapes unchanged', () async {
    final m = _ok(<String, dynamic>{
      'content': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'tool_use',
          'name': 'nope',
          'input': <String, dynamic>{'node_id': 1},
        },
      ],
    });
    final s = ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]);
    expect(() => _p(m).decide(_prompt(), s), throwsA(isA<SchemaRejection>()));
  });

  test('unknown tool wire name → SchemaRejection (unknown tool, available list)',
      () async {
    final m = _ok(<String, dynamic>{
      'content': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'tool_use',
          'name': 'navigate',
          'input': <String, dynamic>{'route_name': 'settings'},
        },
      ],
    });
    final tools = <ToolDescriptor>[_t('core.tap'), _t('router.navigate')];
    final s = ActionSchema.fromToolList(tools);
    final prompt = PromptPayload(
      systemMessage: 'sys',
      userMessages: <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'text': 'go'},
      ],
      tools: tools,
    );
    await expectLater(
      _p(m).decide(prompt, s),
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
                'input': <String, Object?>{'route_name': 'settings'},
              },
            ),
      ),
    );
  });

  test('capabilities: vision toggles by model', () {
    final m = MockClient((_) async => http.Response('', 200));
    expect(_p(m).capabilities.vision, isTrue);
    expect(_p(m, model: 'claude-haiku-4-text').capabilities.vision, isFalse);
    expect(_p(m).capabilities.preserveThinking, isFalse);
    expect(_p(m).capabilities.supportsToolUse, isTrue);
    expect(_p(m).capabilities.maxContext, 200000);
  });

  test('lookupTool maps wire ↔ dotted', () {
    final tools = <ToolDescriptor>[_t('core.tap'), _t('router.push')];
    expect(lookupTool(tools, 'core_tap')?.name, 'core.tap');
    expect(lookupTool(tools, 'router_push')?.name, 'router.push');
    expect(lookupTool(tools, 'unknown_x'), isNull);
  });

  test('validateToolArgs throws on bad args', () {
    expect(
      () => validateToolArgs(_t('core.tap'), <String, dynamic>{
        'node_id': 'nope',
      }),
      throwsA(isA<SchemaRejection>()),
    );
  });

  test('FrontierDefaults values', () {
    expect(FrontierDefaults.temperature, 0.2);
    expect(FrontierDefaults.maxTokens, 4096);
    expect(FrontierDefaults.maxObservationBytes, 6144);
    expect(FrontierDefaults.maxRetries, 1);
  });
}
