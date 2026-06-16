import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:leonard_agent/src/observation/diff_models.dart';
import 'package:leonard_agent/src/observation/models.dart';
import 'package:leonard_agent/src/provider/action_schema.dart';
import 'package:leonard_agent/src/provider/backend/dartantic_model_provider.dart';
import 'package:leonard_agent/src/provider/backend/model_backend.dart';
import 'package:leonard_agent/src/provider/types.dart';
import 'package:test/test.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this.events);
  final List<Map<String, dynamic>> events;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final sb = StringBuffer();
    for (final e in events) {
      sb.write('data: ${jsonEncode(e)}\n\n');
    }
    sb.write('data: [DONE]\n\n');
    return http.StreamedResponse(Stream.value(utf8.encode(sb.toString())), 200);
  }
}

const _caps = ModelCapabilities(
  vision: false,
  preserveThinking: true,
  maxContext: 128000,
  supportsToolUse: true,
);

final _tapTool = ToolDescriptor(
  name: 'core.tap',
  description: 'tap a node',
  inputSchema: const {
    'type': 'object',
    'properties': {
      'nodeId': {'type': 'integer'},
    },
    'required': ['nodeId'],
    'additionalProperties': false,
  },
);

DartanticModelProvider _provider(List<Map<String, dynamic>> sse) =>
    DartanticModelProvider(
      backend: SwiftInferBackend(
        baseUrl: Uri.parse('http://localhost:8080'),
        bearerToken: 'tok',
      ),
      model: 'qwen',
      capabilities: _caps,
      client: _FakeClient(sse),
    );

ConversationSnapshot _snapshot() => ConversationSnapshot(
  systemMessage: 'you are an agent',
  turns: [
    UserTurn(observation: Observation.empty(), diff: ObservationDiff.empty()),
  ],
  tools: [
    ToolDescriptor(
      name: _tapTool.name,
      description: _tapTool.description,
      inputSchema: _tapTool.inputSchema,
    ),
  ],
);

void main() {
  group('DartanticModelProvider.decide', () {
    test('decodes thinking + tool call into a ModelDecision', () async {
      final p = _provider([
        {
          'type': 'message_start',
          'message': {'id': 'msg_42'},
        },
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'thinking_delta', 'thinking': 'find the button'},
        },
        {
          'type': 'content_block_start',
          'index': 1,
          'content_block': {
            'type': 'tool_use',
            'id': 'tu1',
            'name': 'core_tap', // wire form of core.tap
            'input': <String, dynamic>{},
          },
        },
        {
          'type': 'content_block_delta',
          'index': 1,
          'delta': {'type': 'input_json_delta', 'partial_json': '{"nodeId":7}'},
        },
        {'type': 'content_block_stop', 'index': 1},
        {
          'type': 'message_delta',
          'delta': {'stop_reason': 'tool_use'},
        },
      ]);

      final thinkingDeltas = <ThinkingDelta>[];
      final sub = p.thinking().listen(thinkingDeltas.add);

      final decision = await p.decide(
        _snapshot(),
        ActionSchema.fromToolList([_tapTool]),
      );
      // Flush broadcast delivery so the final ThinkingDelta (emitted in decide's
      // finally) reaches the listener before we assert.
      await Future<void>.delayed(Duration.zero);

      expect(decision.action.tool, 'core.tap'); // decoded back to dotted
      expect(decision.action.args, {'nodeId': 7});
      expect(decision.thinking, 'find the button');
      expect(decision.providerRequestId, 'msg_42');
      expect(
        thinkingDeltas.where((d) => !d.isFinal).map((d) => d.text).join(),
        'find the button',
      );
      expect(thinkingDeltas.last.isFinal, isTrue);

      await sub.cancel();
      p.dispose();
    });

    test('throws SchemaRejection when no tool call is emitted', () async {
      final p = _provider([
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'text_delta', 'text': 'I am not sure'},
        },
        {
          'type': 'message_delta',
          'delta': {'stop_reason': 'end_turn'},
        },
      ]);
      await expectLater(
        p.decide(_snapshot(), ActionSchema.fromToolList([_tapTool])),
        throwsA(isA<SchemaRejection>()),
      );
      p.dispose();
    });

    test('throws SchemaRejection on an unknown tool name', () async {
      final p = _provider([
        {
          'type': 'content_block_start',
          'index': 1,
          'content_block': {
            'type': 'tool_use',
            'id': 'tu1',
            'name': 'core_nonexistent',
            'input': <String, dynamic>{},
          },
        },
        {'type': 'content_block_stop', 'index': 1},
        {
          'type': 'message_delta',
          'delta': {'stop_reason': 'tool_use'},
        },
      ]);
      await expectLater(
        p.decide(_snapshot(), ActionSchema.fromToolList([_tapTool])),
        throwsA(
          isA<SchemaRejection>().having(
            (e) => e.validationError,
            'validationError',
            contains('unknown tool'),
          ),
        ),
      );
      p.dispose();
    });

    test('throws SchemaRejection when args violate the ActionSchema', () async {
      final p = _provider([
        {
          'type': 'content_block_start',
          'index': 1,
          'content_block': {
            'type': 'tool_use',
            'id': 'tu1',
            'name': 'core_tap',
            'input': <String, dynamic>{},
          },
        },
        {
          'type': 'content_block_delta',
          'index': 1,
          // missing required nodeId
          'delta': {'type': 'input_json_delta', 'partial_json': '{"wrong":1}'},
        },
        {'type': 'content_block_stop', 'index': 1},
        {
          'type': 'message_delta',
          'delta': {'stop_reason': 'tool_use'},
        },
      ]);
      await expectLater(
        p.decide(_snapshot(), ActionSchema.fromToolList([_tapTool])),
        throwsA(isA<SchemaRejection>()),
      );
      p.dispose();
    });

    test(
      'rejects a namespace-dropped tool name (router.navigate -> navigate)',
      () async {
        // Regression for swift-infer trace msg_333DE0C006B: qwen3.6 emits the
        // bare `navigate` instead of the wire-encoded `router_navigate`. The
        // seam decodes via lookupTool, finds no match, and rejects with the
        // exact message the loop driver/observers key on. (Re-instated offline
        // after provider_loop_integration_test was deleted in the cutover.)
        final navTool = ToolDescriptor(
          name: 'router.navigate',
          description: 'navigate to a route',
          inputSchema: const {
            'type': 'object',
            'properties': <String, dynamic>{},
            'additionalProperties': false,
          },
        );
        final p = _provider([
          {
            'type': 'content_block_start',
            'index': 1,
            'content_block': {
              'type': 'tool_use',
              'id': 'tu1',
              'name': 'navigate', // namespace prefix dropped by the model
              'input': <String, dynamic>{},
            },
          },
          {'type': 'content_block_stop', 'index': 1},
          {
            'type': 'message_delta',
            'delta': {'stop_reason': 'tool_use'},
          },
        ]);
        final snapshot = ConversationSnapshot(
          systemMessage: 'sys',
          turns: [
            UserTurn(
              observation: Observation.empty(),
              diff: ObservationDiff.empty(),
            ),
          ],
          tools: [navTool],
        );
        await expectLater(
          p.decide(snapshot, ActionSchema.fromToolList([navTool])),
          throwsA(
            isA<SchemaRejection>().having(
              (e) => e.validationError,
              'validationError',
              startsWith('model emitted unknown tool: navigate'),
            ),
          ),
        );
        p.dispose();
      },
    );
  });
}
