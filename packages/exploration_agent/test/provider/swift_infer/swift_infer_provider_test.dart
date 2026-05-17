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

SwiftInferConfig _cfg({
  bool vision = false,
  String? bearer,
  bool capture = false,
  String? conversationId,
  String? sessionId,
  Map<String, String> extra = const <String, String>{},
}) =>
    SwiftInferConfig(
      baseUrl: Uri.parse('http://localhost:8080'),
      model: 'qwen3.6-35b-a3b-8bit',
      bearerToken: bearer,
      captureBodies: capture,
      conversationId: conversationId,
      sessionId: sessionId,
      extraHeaders: extra,
      enableVision: vision,
    );

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
  String? text,
}) =>
    _sse(<Map<String, dynamic>>[
      if (text != null)
        <String, dynamic>{
          'type': 'content_block_delta',
          'delta': <String, dynamic>{'type': 'text_delta', 'text': text},
        },
      <String, dynamic>{
        'type': 'content_block_start',
        'content_block': <String, dynamic>{
          'type': 'tool_use',
          'id': 't1',
          'name': name,
        },
      },
      <String, dynamic>{
        'type': 'content_block_delta',
        'delta': <String, dynamic>{
          'type': 'input_json_delta',
          'partial_json': jsonEncode(input),
        },
      },
      <String, dynamic>{'type': 'message_stop'},
    ]);

Map<String, dynamic> _decodeBody(List<int> bytes) =>
    jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

void main() {
  test('happy path: tool_use → ModelDecision', () async {
    final p = SwiftInferModelProvider(
      config: _cfg(),
      client: _stream(_toolUseSse()),
    );
    final d = await p.decide(
      _prompt(),
      ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]),
    );
    expect(d.action.tool, 'core.tap');
    expect(d.action.args['node_id'], 7);
  });

  test('sampling defaults appear in request body', () async {
    Map<String, dynamic>? body;
    final m = _stream(
      _toolUseSse(),
      capture: (_, bytes) => body = _decodeBody(bytes),
    );
    await SwiftInferModelProvider(config: _cfg(), client: m).decide(
      _prompt(),
      ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]),
    );
    expect(body!['temperature'], 1.0);
    expect(body!['top_p'], 0.95);
    expect(body!['top_k'], 20);
    expect(body!['presence_penalty'], 1.5);
    expect(body!['repetition_penalty'], 1.0);
    expect(body!['preserve_thinking'], true);
    expect(body!['stream'], true);
    expect(body!['model'], 'qwen3.6-35b-a3b-8bit');
    expect(body!['max_tokens'], 4096);
    expect(body!['system'], 'sys');
    expect((body!['tools'] as List).length, 1);
  });

  test('vision=false strips image blocks from request', () async {
    Map<String, dynamic>? body;
    final m = _stream(
      _toolUseSse(),
      capture: (_, bytes) => body = _decodeBody(bytes),
    );
    final img = VisionImage.fromPngBytes(Uint8List.fromList(<int>[1, 2, 3]));
    await SwiftInferModelProvider(config: _cfg(vision: false), client: m)
        .decide(
      _prompt(user: <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'text': 'look'},
        img.toAnthropicBlock(),
      ]),
      ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]),
    );
    final content = (body!['messages'] as List)[0]['content'] as List;
    expect(content.where((b) => (b as Map)['type'] == 'image'), isEmpty);
    expect(content.where((b) => (b as Map)['type'] == 'text').length, 1);
  });

  test('vision=true forwards image blocks', () async {
    Map<String, dynamic>? body;
    final m = _stream(
      _toolUseSse(),
      capture: (_, bytes) => body = _decodeBody(bytes),
    );
    final img = VisionImage.fromPngBytes(Uint8List.fromList(<int>[1, 2, 3]));
    await SwiftInferModelProvider(config: _cfg(vision: true), client: m)
        .decide(
      _prompt(user: <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'text': 'look'},
        img.toAnthropicBlock(),
      ]),
      ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]),
    );
    final content = (body!['messages'] as List)[0]['content'] as List;
    final block = content.firstWhere(
      (b) => (b as Map)['type'] == 'image',
    ) as Map;
    expect((block['source'] as Map)['data'], isNotEmpty);
  });

  test('bearerToken omitted when null', () async {
    http.BaseRequest? captured;
    final m = _stream(
      _toolUseSse(),
      capture: (r, _) => captured = r,
    );
    await SwiftInferModelProvider(config: _cfg(), client: m).decide(
      _prompt(),
      ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]),
    );
    expect(captured!.headers.containsKey('authorization'), isFalse);
    expect(captured!.headers.containsKey('x-api-key'), isFalse);
  });

  test('bearerToken → Authorization: Bearer <v>', () async {
    http.BaseRequest? captured;
    final m = _stream(
      _toolUseSse(),
      capture: (r, _) => captured = r,
    );
    await SwiftInferModelProvider(config: _cfg(bearer: 'sk-abc'), client: m)
        .decide(
      _prompt(),
      ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]),
    );
    expect(captured!.headers['authorization'], 'Bearer sk-abc');
    expect(captured!.headers.containsKey('x-api-key'), isFalse);
    expect(captured!.headers['accept'], 'text/event-stream');
    expect(captured!.headers['anthropic-version'], '2023-06-01');
  });

  test('conversationId/sessionId/captureBodies headers set when configured',
      () async {
    http.BaseRequest? captured;
    final m = _stream(
      _toolUseSse(),
      capture: (r, _) => captured = r,
    );
    await SwiftInferModelProvider(
      config: _cfg(
        capture: true,
        conversationId: 'conv-123',
        sessionId: 'sess-xyz',
      ),
      client: m,
    ).decide(
      _prompt(),
      ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]),
    );
    expect(captured!.headers['x-conversation-id'], 'conv-123');
    expect(captured!.headers['x-session-id'], 'sess-xyz');
    expect(captured!.headers['x-swift-infer-capture-bodies'], 'true');
  });

  test('extraHeaders cannot overwrite well-known headers', () async {
    http.BaseRequest? captured;
    final m = _stream(
      _toolUseSse(),
      capture: (r, _) => captured = r,
    );
    await SwiftInferModelProvider(
      config: _cfg(
        bearer: 'sk-real',
        capture: true,
        conversationId: 'real-conv',
        sessionId: 'real-sess',
        extra: const <String, String>{
          'authorization': 'Bearer attacker',
          'x-conversation-id': 'evil',
          'x-session-id': 'evil',
          'x-swift-infer-capture-bodies': 'false',
          'x-custom-trace': 'ok',
        },
      ),
      client: m,
    ).decide(
      _prompt(),
      ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]),
    );
    expect(captured!.headers['authorization'], 'Bearer sk-real');
    expect(captured!.headers['x-conversation-id'], 'real-conv');
    expect(captured!.headers['x-session-id'], 'real-sess');
    expect(captured!.headers['x-swift-infer-capture-bodies'], 'true');
    expect(captured!.headers['x-custom-trace'], 'ok');
  });

  test('missing tool_use → SchemaRejection', () async {
    final body = _sse(<Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'content_block_delta',
        'delta': <String, dynamic>{
          'type': 'text_delta',
          'text': 'no tool here',
        },
      },
      <String, dynamic>{'type': 'message_stop'},
    ]);
    final p = SwiftInferModelProvider(config: _cfg(), client: _stream(body));
    expect(
      () => p.decide(
        _prompt(),
        ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]),
      ),
      throwsA(
        isA<SchemaRejection>().having(
          (e) => e.validationError,
          'err',
          contains('no tool_use block'),
        ),
      ),
    );
  });

  test('ActionSchema rejection escapes unchanged', () async {
    final p = SwiftInferModelProvider(
      config: _cfg(),
      client: _stream(_toolUseSse(name: 'unknown_x')),
    );
    expect(
      () => p.decide(
        _prompt(),
        ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]),
      ),
      throwsA(isA<SchemaRejection>()),
    );
  });

  test('unknown tool wire name → SchemaRejection (unknown tool, available list)',
      () async {
    final p = SwiftInferModelProvider(
      config: _cfg(),
      client: _stream(_toolUseSse(
        name: 'navigate',
        input: <String, dynamic>{'route_name': 'settings'},
      )),
    );
    final tools = <ToolDescriptor>[_t('core.tap'), _t('router.navigate')];
    final prompt = PromptPayload(
      systemMessage: 'sys',
      userMessages: <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'text': 'hi'},
      ],
      tools: tools,
    );
    await expectLater(
      p.decide(prompt, ActionSchema.fromToolList(tools)),
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

  test('thinking stream emits ThinkingDelta as SSE chunks arrive', () async {
    final body = _sse(<Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'content_block_delta',
        'delta': <String, dynamic>{
          'type': 'text_delta',
          'text': '<think>step ',
        },
      },
      <String, dynamic>{
        'type': 'content_block_delta',
        'delta': <String, dynamic>{
          'type': 'text_delta',
          'text': 'one</think>',
        },
      },
      <String, dynamic>{
        'type': 'content_block_start',
        'content_block': <String, dynamic>{
          'type': 'tool_use',
          'id': 't1',
          'name': 'core_tap',
        },
      },
      <String, dynamic>{
        'type': 'content_block_delta',
        'delta': <String, dynamic>{
          'type': 'input_json_delta',
          'partial_json': '{"node_id":1}',
        },
      },
      <String, dynamic>{'type': 'message_stop'},
    ]);
    final p = SwiftInferModelProvider(config: _cfg(), client: _stream(body));
    final deltas = <ThinkingDelta>[];
    final sub = p.thinking().listen(deltas.add);
    await p.decide(
      _prompt(),
      ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]),
    );
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(deltas.map((d) => d.text).toList(), <String>['step ', 'one', '']);
    expect(deltas.last.isFinal, isTrue);
  });

  test('thinking stream emits ThinkingDelta from Anthropic-native '
      'thinking_delta events', () async {
    final body = _sse(<Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'content_block_start',
        'index': 0,
        'content_block': <String, dynamic>{'type': 'thinking', 'thinking': ''},
      },
      <String, dynamic>{
        'type': 'content_block_delta',
        'index': 0,
        'delta': <String, dynamic>{
          'type': 'thinking_delta',
          'thinking': 'Here',
        },
      },
      <String, dynamic>{
        'type': 'content_block_delta',
        'index': 0,
        'delta': <String, dynamic>{
          'type': 'thinking_delta',
          'thinking': "'s",
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
          'partial_json': '{"node_id":1}',
        },
      },
      <String, dynamic>{'type': 'content_block_stop', 'index': 1},
      <String, dynamic>{'type': 'message_stop'},
    ]);
    final p = SwiftInferModelProvider(config: _cfg(), client: _stream(body));
    final deltas = <ThinkingDelta>[];
    final sub = p.thinking().listen(deltas.add);
    await p.decide(
      _prompt(),
      ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]),
    );
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(deltas.map((d) => d.text).toList(), <String>['Here', "'s", '']);
    expect(deltas.last.isFinal, isTrue);
  });

  test('captures message.id from message_start as providerRequestId',
      () async {
    final body = _sse(<Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'message_start',
        'message': <String, dynamic>{
          'id': 'msg_5C16E942855',
          'type': 'message',
          'role': 'assistant',
        },
      },
      <String, dynamic>{
        'type': 'content_block_start',
        'content_block': <String, dynamic>{
          'type': 'tool_use',
          'id': 't1',
          'name': 'core_tap',
        },
      },
      <String, dynamic>{
        'type': 'content_block_delta',
        'delta': <String, dynamic>{
          'type': 'input_json_delta',
          'partial_json': jsonEncode(<String, dynamic>{'node_id': 7}),
        },
      },
      <String, dynamic>{'type': 'message_stop'},
    ]);
    final p = SwiftInferModelProvider(
      config: _cfg(),
      client: _stream(body),
    );
    final d = await p.decide(
      _prompt(),
      ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]),
    );
    expect(d.providerRequestId, 'msg_5C16E942855');
  });

  test('providerRequestId is null when message_start is absent', () async {
    final p = SwiftInferModelProvider(
      config: _cfg(),
      client: _stream(_toolUseSse()),
    );
    final d = await p.decide(
      _prompt(),
      ActionSchema.fromToolList(<ToolDescriptor>[_t('core.tap')]),
    );
    expect(d.providerRequestId, isNull);
  });

  test('capabilities reflect config', () {
    final m = _stream('');
    final p1 =
        SwiftInferModelProvider(config: _cfg(vision: false), client: m);
    expect(p1.capabilities.vision, isFalse);
    expect(p1.capabilities.preserveThinking, isTrue);
    expect(p1.capabilities.supportsToolUse, isTrue);
    expect(p1.capabilities.maxContext, 128000);
    final p2 =
        SwiftInferModelProvider(config: _cfg(vision: true), client: m);
    expect(p2.capabilities.vision, isTrue);
  });
}
