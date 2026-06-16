// DIAGNOSTIC: proves whether per-turn observation context survives onto the
// wire for each backend. Drives the REAL DartanticModelProvider.decide() with a
// capturing HTTP client and a 3-turn conversation whose SECOND observation
// carries a unique marker. If the marker is absent from the captured request,
// the backend's mapper dropped the observation (the agent goes blind after
// turn 0).
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:leonard_agent/src/observation/diff_models.dart';
import 'package:leonard_agent/src/observation/models.dart';
import 'package:leonard_agent/src/provider/action_schema.dart';
import 'package:leonard_agent/src/provider/backend/dartantic_model_provider.dart';
import 'package:leonard_agent/src/provider/backend/model_backend.dart';
import 'package:leonard_agent/src/provider/types.dart';
import 'package:test/test.dart';

const _obs0Marker = 'MARKER_OBS0_LOGIN_SCREEN';
const _obs1Marker = 'MARKER_OBS1_DARKMODE_TOGGLE';

/// Captures the outgoing request body, then returns a benign 200 so decide()
/// can finish (or throw — we only care about the captured request).
class _CapturingClient extends http.BaseClient {
  String? body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) body = request.body;
    // Minimal valid-ish SSE so parsing doesn't hard-crash before we return.
    return http.StreamedResponse(
      Stream.value(utf8.encode('data: [DONE]\n\n')),
      200,
    );
  }
}

Observation _obsWith(String marker) => Observation.fromJson(<String, dynamic>{
  'semantics': <Map<String, dynamic>>[
    {
      'id': 8,
      'role': 'button',
      'label': marker,
      'actions': <String>['tap'],
      'rect': <int>[0, 0, 100, 40],
    },
  ],
  'routes': <String>['home'],
});

/// A realistic post-turn-0 conversation: obs0 → assistant tap → obs1(+result).
ConversationSnapshot _threeTurnSnapshot() => ConversationSnapshot(
  systemMessage: 'you are an agent driving an app',
  turns: <ConversationTurn>[
    UserTurn(observation: _obsWith(_obs0Marker), diff: ObservationDiff.empty()),
    const AssistantTurn(
      thinking: 'tapping settings',
      action: (tool: 'core.tap', args: {'node_id': 8}),
    ),
    UserTurn(
      observation: _obsWith(_obs1Marker),
      diff: ObservationDiff.empty(),
      toolResult: const {'ok': true},
    ),
  ],
  tools: <ToolDescriptor>[
    const ToolDescriptor(
      name: 'core.tap',
      description: 'tap a node',
      inputSchema: {
        'type': 'object',
        'properties': {
          'node_id': {'type': 'integer'},
        },
        'required': ['node_id'],
        'additionalProperties': false,
      },
    ),
  ],
);

const _caps = ModelCapabilities(
  vision: false,
  preserveThinking: true,
  maxContext: 128000,
  supportsToolUse: true,
);

Future<String> _captureRequestBody(ModelBackendSpec backend) async {
  final client = _CapturingClient();
  final provider = DartanticModelProvider(
    backend: backend,
    model: backend is AnthropicBackend ? 'claude-sonnet-4-6' : 'qwen',
    capabilities: _caps,
    client: client,
  );
  final snapshot = _threeTurnSnapshot();
  final schema = ActionSchema.fromToolList(snapshot.tools);
  try {
    await provider.decide(snapshot, schema);
  } on Object {
    // decide() may throw on the canned response; we only need the request.
  }
  return client.body ?? '';
}

void main() {
  test(
    'CONTEXT-SURVIVAL: turn-1 observation on the wire, per backend',
    () async {
      final anthropic = await _captureRequestBody(
        const AnthropicBackend(apiKey: 'k'),
      );
      final swift = await _captureRequestBody(
        SwiftInferBackend(baseUrl: Uri.parse('http://localhost:8080')),
      );

      final anthropicHasObs1 = anthropic.contains(_obs1Marker);
      final swiftHasObs1 = swift.contains(_obs1Marker);

      // ignore: avoid_print
      print('\n================ CONTEXT-SURVIVAL DIAGNOSTIC ================');
      // ignore: avoid_print
      print(
        'Anthropic  turn-0 obs ($_obs0Marker): '
        '${anthropic.contains(_obs0Marker)}',
      );
      // ignore: avoid_print
      print(
        'Anthropic  turn-1 obs ($_obs1Marker): $anthropicHasObs1   '
        '<-- false means Claude went BLIND after turn 0',
      );
      // ignore: avoid_print
      print('swift-infer turn-1 obs ($_obs1Marker): $swiftHasObs1');
      // ignore: avoid_print
      print('Anthropic request length: ${anthropic.length} bytes');
      // ignore: avoid_print
      print('============================================================\n');

      // Document the contrast: swift-infer keeps it (Qwen works); this asserts
      // the bug exists on the Anthropic path so it stays visible until fixed.
      expect(swiftHasObs1, isTrue, reason: 'swift-infer should keep the obs');
      expect(
        anthropicHasObs1,
        isTrue,
        reason:
            'Anthropic wire DROPPED the turn-1 observation — the agent is '
            'driven blind after turn 0. This is the systemic context-loss bug.',
      );
    },
  );
}
