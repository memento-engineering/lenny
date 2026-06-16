import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:leonard_agent/src/provider/swift_infer/swift_infer_chat_model.dart';
import 'package:leonard_agent/src/provider/swift_infer/swift_infer_chat_options.dart';
import 'package:test/test.dart';

/// A fake [http.Client] that records the request and replays a canned SSE
/// event sequence as the streamed response body.
class _FakeClient extends http.BaseClient {
  _FakeClient(this.events, {this.status = 200, this.errorBody = ''});

  final List<Map<String, dynamic>> events;
  final int status;
  final String errorBody;

  http.BaseRequest? captured;
  String capturedBody = '';
  var closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    captured = request;
    capturedBody = request is http.Request ? request.body : '';
    if (status >= 400) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(errorBody)),
        status,
      );
    }
    final sb = StringBuffer();
    for (final e in events) {
      sb.write('data: ${jsonEncode(e)}\n\n');
    }
    sb.write('data: [DONE]\n\n');
    return http.StreamedResponse(
      Stream.value(utf8.encode(sb.toString())),
      status,
    );
  }

  @override
  void close() => closed = true;
}

Future<List<ChatResult<ChatMessage>>> _run(
  _FakeClient client, {
  List<Tool>? tools,
  SwiftInferChatOptions? options,
  List<ChatMessage>? messages,
}) async {
  final model = SwiftInferChatModel(
    name: 'qwen-test',
    baseUrl: Uri.parse('http://localhost:9999'),
    bearerToken: 'tok',
    tools: tools,
    headers: const {'x-conversation-id': 'c1'},
    client: client,
    defaultOptions: options,
  );
  final out = <ChatResult<ChatMessage>>[];
  await for (final r in model.sendStream(
    messages ?? [ChatMessage.user('hi')],
  )) {
    out.add(r);
  }
  model.dispose();
  return out;
}

List<Part> _parts(List<ChatResult<ChatMessage>> rs) => [
  for (final r in rs) ...r.output.parts,
];

Map<String, dynamic> _msgStart(String id) => {
  'type': 'message_start',
  'message': {'id': id, 'model': 'qwen-test'},
};
Map<String, dynamic> _textDelta(String t, {int index = 0}) => {
  'type': 'content_block_delta',
  'index': index,
  'delta': {'type': 'text_delta', 'text': t},
};
Map<String, dynamic> _thinkingDelta(String t, {int index = 0}) => {
  'type': 'content_block_delta',
  'index': index,
  'delta': {'type': 'thinking_delta', 'thinking': t},
};
Map<String, dynamic> _toolStart(
  String id,
  String name, {
  int index = 1,
  Map<String, dynamic> input = const {},
}) => {
  'type': 'content_block_start',
  'index': index,
  'content_block': {'type': 'tool_use', 'id': id, 'name': name, 'input': input},
};
Map<String, dynamic> _inputJson(String partial, {int index = 1}) => {
  'type': 'content_block_delta',
  'index': index,
  'delta': {'type': 'input_json_delta', 'partial_json': partial},
};
Map<String, dynamic> _blockStop({int index = 1}) => {
  'type': 'content_block_stop',
  'index': index,
};
Map<String, dynamic> _msgDelta(String stopReason) => {
  'type': 'message_delta',
  'delta': {'stop_reason': stopReason},
};

void main() {
  group('SwiftInferChatModel — SSE decode', () {
    test('streams native thinking_delta as ThinkingPart', () async {
      final rs = await _run(
        _FakeClient([
          _msgStart('msg_1'),
          _thinkingDelta('let me think'),
          _textDelta('done'),
        ]),
      );
      final thinking = _parts(rs).whereType<ThinkingPart>().toList();
      expect(thinking, hasLength(1));
      expect(thinking.single.text, 'let me think');
    });

    test('streams text_delta as TextPart', () async {
      final rs = await _run(_FakeClient([_textDelta('hello world')]));
      final text = _parts(rs).whereType<TextPart>().map((p) => p.text).join();
      expect(text, 'hello world');
    });

    test(
      'routes inline <think>..</think> in text_delta to ThinkingPart',
      () async {
        final rs = await _run(
          _FakeClient([_textDelta('pre<think>reason</think>post')]),
        );
        final parts = _parts(rs);
        expect(parts.whereType<TextPart>().map((p) => p.text).toList(), [
          'pre',
          'post',
        ]);
        expect(parts.whereType<ThinkingPart>().single.text, 'reason');
      },
    );

    test('carries <think> state across text_delta chunks', () async {
      final rs = await _run(
        _FakeClient([_textDelta('a<think>r1'), _textDelta('r2</think>b')]),
      );
      final parts = _parts(rs);
      expect(parts.whereType<ThinkingPart>().map((p) => p.text).join(), 'r1r2');
      expect(parts.whereType<TextPart>().map((p) => p.text).join(), 'ab');
    });

    test(
      'accumulates input_json_delta into a single ToolPart.call at stop',
      () async {
        final rs = await _run(
          _FakeClient([
            _toolStart('toolu_1', 'report_status'),
            _inputJson('{"ok":'),
            _inputJson(' true,"note":"hi"}'),
            _blockStop(),
          ]),
        );
        final tools = _parts(rs).whereType<ToolPart>().toList();
        expect(tools, hasLength(1));
        expect(tools.single.kind, ToolPartKind.call);
        expect(tools.single.callId, 'toolu_1');
        expect(tools.single.toolName, 'report_status');
        expect(tools.single.arguments, {'ok': true, 'note': 'hi'});
      },
    );

    test('uses seed args when no input_json_delta arrives', () async {
      final rs = await _run(
        _FakeClient([
          _toolStart('toolu_2', 'noop', input: {'seed': 1}),
          _blockStop(),
        ]),
      );
      final tool = _parts(rs).whereType<ToolPart>().single;
      expect(tool.arguments, {'seed': 1});
    });

    test('maps stop_reason to FinishReason', () async {
      Future<FinishReason> finishFor(String reason) async {
        final rs = await _run(_FakeClient([_msgDelta(reason)]));
        return rs
            .map((r) => r.finishReason)
            .firstWhere(
              (f) => f != FinishReason.unspecified,
              orElse: () => FinishReason.unspecified,
            );
      }

      expect(await finishFor('tool_use'), FinishReason.toolCalls);
      expect(await finishFor('end_turn'), FinishReason.stop);
      expect(await finishFor('max_tokens'), FinishReason.length);
    });

    test('captures message id onto ChatResult.id', () async {
      final rs = await _run(
        _FakeClient([_msgStart('msg_42'), _textDelta('x')]),
      );
      expect(rs.where((r) => r.output.parts.isNotEmpty).first.id, 'msg_42');
    });

    test('tolerates keep-alive / non-JSON data lines', () async {
      // A raw ping object is ignored; malformed lines are skipped by jsonDecode
      // guard. Here the event list is valid JSON; the [DONE] sentinel and the
      // implicit blank lines exercise the skip paths.
      final rs = await _run(
        _FakeClient([
          {'type': 'ping'},
          _textDelta('ok'),
        ]),
      );
      expect(_parts(rs).whereType<TextPart>().single.text, 'ok');
    });
  });

  group('SwiftInferChatModel — request building', () {
    test('body carries Qwen sampling knobs, tool_choice and system', () async {
      final tool = Tool(
        name: 'report_status',
        description: 'report',
        inputSchema: S.object(
          properties: {'ok': S.boolean()},
          required: ['ok'],
        ),
        onCall: (a) async => 'ok',
      );
      final client = _FakeClient([_textDelta('x')]);
      await _run(
        client,
        tools: [tool],
        messages: [ChatMessage.system('sys prompt'), ChatMessage.user('go')],
      );
      final body = jsonDecode(client.capturedBody) as Map<String, dynamic>;
      expect(body['model'], 'qwen-test');
      expect(body['top_k'], 20);
      expect(body['presence_penalty'], 1.5);
      expect(body['repetition_penalty'], 1.0);
      expect(body['preserve_thinking'], true);
      expect(body['stream'], true);
      expect(body['system'], 'sys prompt');
      expect((body['tool_choice'] as Map<String, dynamic>)['type'], 'any');
      final tools = body['tools'] as List;
      expect((tools.single as Map<String, dynamic>)['name'], 'report_status');
      expect(
        (tools.single as Map<String, dynamic>)['input_schema'],
        isA<Map<String, dynamic>>(),
      );
    });

    test('tool_choice auto when configured', () async {
      final tool = Tool(
        name: 't',
        description: 'd',
        inputSchema: S.object(),
        onCall: (a) async => 'ok',
      );
      final client = _FakeClient([_textDelta('x')]);
      await _run(
        client,
        tools: [tool],
        options: const SwiftInferChatOptions(
          toolChoice: SwiftInferToolChoice.auto,
        ),
      );
      final body = jsonDecode(client.capturedBody) as Map<String, dynamic>;
      expect((body['tool_choice'] as Map<String, dynamic>)['type'], 'auto');
    });

    test('well-known headers win over caller headers; bearer set', () async {
      final client = _FakeClient([_textDelta('x')]);
      final model = SwiftInferChatModel(
        name: 'qwen-test',
        baseUrl: Uri.parse('http://localhost:9999'),
        bearerToken: 'secret',
        headers: const {'content-type': 'text/plain', 'x-session-id': 's1'},
        client: client,
      );
      await model.sendStream([ChatMessage.user('hi')]).drain<void>();
      final h = client.captured!.headers;
      expect(h['content-type'], 'application/json'); // well-known wins
      expect(h['accept'], 'text/event-stream');
      expect(h['anthropic-version'], '2023-06-01');
      expect(h['authorization'], 'Bearer secret');
      expect(h['x-session-id'], 's1'); // caller extra preserved
    });

    test('posts to /v1/messages on the bare origin', () async {
      final client = _FakeClient([_textDelta('x')]);
      await _run(client);
      expect(
        client.captured!.url.toString(),
        'http://localhost:9999/v1/messages',
      );
    });

    test('maps model tool_use and user tool_result into wire blocks', () async {
      final client = _FakeClient([_textDelta('x')]);
      await _run(
        client,
        messages: [
          ChatMessage.user('first'),
          ChatMessage(
            role: ChatMessageRole.model,
            parts: [
              ThinkingPart('because'),
              ToolPart.call(
                callId: 'tu1',
                toolName: 'tap',
                arguments: {'x': 1},
              ),
            ],
          ),
          ChatMessage(
            role: ChatMessageRole.user,
            parts: [
              ToolPart.result(callId: 'tu1', toolName: 'tap', result: 'done'),
            ],
          ),
        ],
      );
      final body = jsonDecode(client.capturedBody) as Map<String, dynamic>;
      final msgs = (body['messages'] as List).cast<Map<String, dynamic>>();
      // model turn: <think> replay + tool_use
      final model = msgs[1];
      final modelContent = (model['content'] as List)
          .cast<Map<String, dynamic>>();
      expect(modelContent.first['type'], 'text');
      expect(modelContent.first['text'], '<think>because</think>');
      final toolUse = modelContent.firstWhere((c) => c['type'] == 'tool_use');
      expect(toolUse['id'], 'tu1');
      expect(toolUse['name'], 'tap');
      expect(toolUse['input'], {'x': 1});
      // tool result turn
      final resultTurn = msgs[2];
      final resultBlock = (resultTurn['content'] as List)
          .cast<Map<String, dynamic>>()
          .single;
      expect(resultBlock['type'], 'tool_result');
      expect(resultBlock['tool_use_id'], 'tu1');
      expect(resultBlock['content'], 'done');
    });
  });

  group('SwiftInferChatModel — contracts', () {
    test(
      'non-2xx throws SwiftInferHttpException after draining body',
      () async {
        final client = _FakeClient(const [], status: 503, errorBody: 'boom');
        expect(
          () => _run(client),
          throwsA(
            isA<SwiftInferHttpException>()
                .having((e) => e.statusCode, 'statusCode', 503)
                .having((e) => e.body, 'body', 'boom'),
          ),
        );
      },
    );

    test('does NOT close a supplied client on dispose', () async {
      final client = _FakeClient([_textDelta('x')]);
      await _run(client); // _run calls dispose()
      expect(client.closed, isFalse);
    });

    test('default options match SwiftInferConfig defaults', () {
      const o = SwiftInferChatOptions();
      expect(o.maxTokens, 4096);
      expect(o.temperature, 1.0);
      expect(o.topP, 0.95);
      expect(o.topK, 20);
      expect(o.presencePenalty, 1.5);
      expect(o.repetitionPenalty, 1.0);
      expect(o.preserveThinking, true);
      expect(o.toolChoice, SwiftInferToolChoice.any);
    });
  });

  group('SwiftInferChatModel — hardening (from adversarial review)', () {
    test('handles a <think> marker split across text_delta chunks', () async {
      final rs = await _run(
        _FakeClient([_textDelta('a<thi'), _textDelta('nk>r</think>b')]),
      );
      final parts = _parts(rs);
      expect(parts.whereType<TextPart>().map((p) => p.text).join(), 'ab');
      expect(parts.whereType<ThinkingPart>().map((p) => p.text).join(), 'r');
    });

    test(
      'degrades malformed tool-args JSON to empty without throwing',
      () async {
        final rs = await _run(
          _FakeClient([
            _toolStart('t1', 'f'),
            _inputJson('{"ok": tru'), // truncated (e.g. qwen hit max_tokens)
            _blockStop(),
          ]),
        );
        final tool = _parts(rs).whereType<ToolPart>().single;
        expect(tool.arguments, isEmpty);
      },
    );

    test(
      'flushes a pending tool call when the stream ends without stop',
      () async {
        final rs = await _run(
          _FakeClient([
            _toolStart('t2', 'f'),
            _inputJson('{"ok":true}'),
            _msgDelta('tool_use'), // finish, but NO content_block_stop
          ]),
        );
        final tool = _parts(rs).whereType<ToolPart>().single;
        expect(tool.callId, 't2');
        expect(tool.arguments, {'ok': true});
      },
    );

    test('retains seed args when input_json_delta is empty', () async {
      final rs = await _run(
        _FakeClient([
          _toolStart('t3', 'f', input: {'seed': 9}),
          _inputJson(''), // empty delta must not drop the seed
          _blockStop(),
        ]),
      );
      expect(_parts(rs).whereType<ToolPart>().single.arguments, {'seed': 9});
    });

    test('extracts token usage from message_start and message_delta', () async {
      final rs = await _run(
        _FakeClient([
          {
            'type': 'message_start',
            'message': {
              'id': 'm',
              'usage': {'input_tokens': 12},
            },
          },
          _textDelta('x'),
          {
            'type': 'message_delta',
            'delta': {'stop_reason': 'end_turn'},
            'usage': {'output_tokens': 34},
          },
        ]),
      );
      final usage = rs.map((r) => r.usage).whereType<LanguageModelUsage>().last;
      expect(usage.promptTokens, 12);
      expect(usage.responseTokens, 34);
      expect(usage.totalTokens, 46);
    });

    test(
      'merges tool_result with accompanying text in one user turn',
      () async {
        final client = _FakeClient([_textDelta('x')]);
        await _run(
          client,
          messages: [
            ChatMessage(
              role: ChatMessageRole.user,
              parts: [
                ToolPart.result(callId: 'tu1', toolName: 't', result: 'done'),
                TextPart('and more context'),
              ],
            ),
          ],
        );
        final body = jsonDecode(client.capturedBody) as Map<String, dynamic>;
        final content =
            ((body['messages'] as List).single
                    as Map<String, dynamic>)['content']
                as List;
        expect(content, hasLength(2));
        expect((content[0] as Map<String, dynamic>)['type'], 'tool_result');
        expect((content[1] as Map<String, dynamic>)['type'], 'text');
        expect(
          (content[1] as Map<String, dynamic>)['text'],
          'and more context',
        );
      },
    );

    test('skips a model message that serialises to empty content', () async {
      final client = _FakeClient([_textDelta('x')]);
      await _run(
        client,
        options: const SwiftInferChatOptions(preserveThinking: false),
        messages: [
          ChatMessage.user('hi'),
          // thinking-only with preserveThinking off -> empty content -> dropped
          ChatMessage(role: ChatMessageRole.model, parts: [ThinkingPart('t')]),
        ],
      );
      final body = jsonDecode(client.capturedBody) as Map<String, dynamic>;
      expect((body['messages'] as List), hasLength(1));
    });
  });
}
