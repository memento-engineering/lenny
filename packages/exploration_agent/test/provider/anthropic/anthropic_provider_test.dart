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

String _sse(List<Map<String, dynamic>> events) =>
    events.map((e) => 'data: ${jsonEncode(e)}\n\n').join();

MockClient _stream(
  String body, {
  void Function(http.BaseRequest req, List<int> bodyBytes)? capture,
}) =>
    MockClient.streaming((req, bodyStream) async {
      final bytes = await bodyStream
          .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
      capture?.call(req, bytes);
      return http.StreamedResponse(
        Stream<List<int>>.fromIterable(<List<int>>[utf8.encode(body)]),
        200,
        headers: <String, String>{'content-type': 'text/event-stream'},
      );
    });

String _toolUseSse({
  String name = 'core_tap',
  Map<String, dynamic> input = const <String, dynamic>{'node_id': 7},
}) =>
    _sse(<Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'content_block_start',
        'index': 0,
        'content_block': <String, dynamic>{
          'type': 'tool_use',
          'id': 't1',
          'name': name,
        },
      },
      <String, dynamic>{
        'type': 'content_block_delta',
        'index': 0,
        'delta': <String, dynamic>{
          'type': 'input_json_delta',
          'partial_json': jsonEncode(input),
        },
      },
      <String, dynamic>{'type': 'content_block_stop', 'index': 0},
      <String, dynamic>{'type': 'message_stop'},
    ]);

Map<String, dynamic> _decodeBody(List<int> bytes) =>
    jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

void main() {
  test('happy path: tool_use → ModelDecision', () async {
    final m = _stream(_toolUseSse());
    final s = ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]);
    final d = await _p(m).decide(_prompt(), s);
    expect(d.action.tool, 'core.tap');
    expect(d.action.args['node_id'], 7);
  });

  test('request body forces a tool call via tool_choice:any', () async {
    Map<String, dynamic>? sent;
    final m = _stream(
      _toolUseSse(),
      capture: (req, bytes) => sent = _decodeBody(bytes),
    );
    final s = ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]);
    await _p(m).decide(_prompt(), s);
    expect(sent, isNotNull);
    expect(
      sent!['tool_choice'],
      <String, dynamic>{'type': 'any'},
      reason: 'the agent must emit a tool_use block every turn; '
          'tool_choice:auto lets the model answer in prose, which '
          'decide() rejects as "no tool_use block in response"',
    );
  });

  test('onCallDiagnostics fires with timing + status on a successful call',
      () async {
    Map<String, Object?>? diag;
    final m = _stream(_toolUseSse());
    final p = AnthropicModelProvider(
      model: 'claude-sonnet-4-6',
      apiKey: 'k',
      client: m,
      onCallDiagnostics: (d) => diag = d,
    );
    final s = ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]);
    await p.decide(_prompt(), s);
    expect(diag, isNotNull);
    expect(diag!['provider'], 'anthropic');
    expect(diag!['ok'], isTrue);
    expect(diag!['http_status'], 200);
    expect(diag!['tool_use'], isTrue);
    expect(diag!['duration_ms'], isA<int>());
    expect(diag!.containsKey('error'), isFalse);
  });

  test('onCallDiagnostics fires with ok:false + error on a failed call',
      () async {
    Map<String, Object?>? diag;
    final body = _sse(<Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'content_block_start',
        'index': 0,
        'content_block': <String, dynamic>{'type': 'text'},
      },
      <String, dynamic>{'type': 'message_stop'},
    ]);
    final p = AnthropicModelProvider(
      model: 'claude-sonnet-4-6',
      apiKey: 'k',
      client: _stream(body),
      onCallDiagnostics: (d) => diag = d,
    );
    final s = ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]);
    await expectLater(
      () => p.decide(_prompt(), s),
      throwsA(isA<SchemaRejection>()),
    );
    expect(diag, isNotNull);
    expect(diag!['ok'], isFalse);
    expect(diag!['tool_use'], isFalse);
    expect(diag!['error'], contains('no tool_use block'));
  });

  test('missing tool_use → SchemaRejection', () async {
    final body = _sse(<Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'content_block_start',
        'index': 0,
        'content_block': <String, dynamic>{'type': 'text'},
      },
      <String, dynamic>{
        'type': 'content_block_delta',
        'index': 0,
        'delta': <String, dynamic>{'type': 'text_delta', 'text': 'no'},
      },
      <String, dynamic>{'type': 'content_block_stop', 'index': 0},
      <String, dynamic>{'type': 'message_stop'},
    ]);
    final m = _stream(body);
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
    final m = _stream(
      _toolUseSse(input: const <String, dynamic>{'node_id': 1}),
      capture: (_, bytes) => captured = _decodeBody(bytes),
    );
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
    final m = _stream(_toolUseSse(
      name: 'nope',
      input: const <String, dynamic>{'node_id': 1},
    ));
    final s = ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]);
    expect(() => _p(m).decide(_prompt(), s), throwsA(isA<SchemaRejection>()));
  });

  test('unknown tool wire name → SchemaRejection (unknown tool, available list)',
      () async {
    final m = _stream(_toolUseSse(
      name: 'navigate',
      input: const <String, dynamic>{'route_name': 'settings'},
    ));
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

  test('thinking stream emits ThinkingDelta from thinking_delta events',
      () async {
    final body = _sse(<Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'content_block_start',
        'index': 0,
        'content_block': <String, dynamic>{'type': 'thinking'},
      },
      <String, dynamic>{
        'type': 'content_block_delta',
        'index': 0,
        'delta': <String, dynamic>{
          'type': 'thinking_delta',
          'thinking': 'reason',
        },
      },
      <String, dynamic>{
        'type': 'content_block_delta',
        'index': 0,
        'delta': <String, dynamic>{
          'type': 'thinking_delta',
          'thinking': 'ing',
        },
      },
      <String, dynamic>{'type': 'content_block_stop', 'index': 0},
      <String, dynamic>{
        'type': 'content_block_start',
        'index': 1,
        'content_block': <String, dynamic>{
          'type': 'tool_use',
          'id': 't1',
          'name': 'core_tap',
        },
      },
      <String, dynamic>{
        'type': 'content_block_delta',
        'index': 1,
        'delta': <String, dynamic>{
          'type': 'input_json_delta',
          'partial_json': '{"node_id":7}',
        },
      },
      <String, dynamic>{'type': 'content_block_stop', 'index': 1},
      <String, dynamic>{'type': 'message_stop'},
    ]);
    final p = AnthropicModelProvider(
      model: 'claude-sonnet-4-6',
      apiKey: 'k',
      client: _stream(body),
    );
    final deltas = <ThinkingDelta>[];
    final sub = p.thinking().listen(deltas.add);
    final d = await p.decide(
      _prompt(),
      ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]),
    );
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(d.action.tool, 'core.tap');
    expect(d.action.args['node_id'], 7);
    expect(deltas.map((e) => e.text).toList(),
        <String>['reason', 'ing', '']);
    expect(deltas.last.isFinal, isTrue);
  });

  test('captures message.id from message_start as providerRequestId',
      () async {
    final body = _sse(<Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'message_start',
        'message': <String, dynamic>{
          'id': 'msg_anthropic_1',
          'type': 'message',
          'role': 'assistant',
        },
      },
      <String, dynamic>{
        'type': 'content_block_start',
        'index': 0,
        'content_block': <String, dynamic>{
          'type': 'tool_use',
          'id': 't1',
          'name': 'core_tap',
        },
      },
      <String, dynamic>{
        'type': 'content_block_delta',
        'index': 0,
        'delta': <String, dynamic>{
          'type': 'input_json_delta',
          'partial_json': jsonEncode(<String, dynamic>{'node_id': 7}),
        },
      },
      <String, dynamic>{'type': 'content_block_stop', 'index': 0},
      <String, dynamic>{'type': 'message_stop'},
    ]);
    final s = ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]);
    final d = await _p(_stream(body)).decide(_prompt(), s);
    expect(d.providerRequestId, 'msg_anthropic_1');
  });

  test('providerRequestId is null when message_start is absent', () async {
    final s = ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]);
    final d = await _p(_stream(_toolUseSse())).decide(_prompt(), s);
    expect(d.providerRequestId, isNull);
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
