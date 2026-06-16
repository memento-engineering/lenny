// Live end-to-end validation for lenny-4dhv.3: drive a real swift-infer turn
// through the DartanticModelProvider seam (ConversationSnapshot -> dartantic
// ChatModel -> ModelDecision), confirming tool decode + ActionSchema validation.
//
// Run: cd packages/leonard_agent && \
//   SWIFT_INFER_AGENT_TOKEN=... dart run tool/live_seam_probe.dart
import 'dart:io';

import 'package:leonard_agent/src/observation/diff_models.dart';
import 'package:leonard_agent/src/observation/models.dart';
import 'package:leonard_agent/src/provider/action_schema.dart';
import 'package:leonard_agent/src/provider/backend/dartantic_model_provider.dart';
import 'package:leonard_agent/src/provider/backend/model_backend.dart';
import 'package:leonard_agent/src/provider/types.dart';

Future<void> main() async {
  final token = Platform.environment['SWIFT_INFER_AGENT_TOKEN'] ?? '';
  if (token.isEmpty) {
    stderr.writeln('SWIFT_INFER_AGENT_TOKEN missing');
    exit(2);
  }

  final tool = ToolDescriptor(
    name: 'report.status',
    description:
        'Report the health check result. You MUST call this to answer.',
    inputSchema: const {
      'type': 'object',
      'properties': {
        'status': {'type': 'string'},
        'note': {'type': 'string'},
      },
      'required': ['status', 'note'],
      'additionalProperties': false,
    },
  );

  final provider = DartanticModelProvider(
    backend: SwiftInferBackend(
      baseUrl: Uri.parse('http://localhost:8080'),
      bearerToken: token,
      headers: const {'x-conversation-id': 'spike-4dhv3'},
    ),
    model: 'qwen3.6-35b-a3b-8bit',
    capabilities: const ModelCapabilities(
      vision: false,
      preserveThinking: true,
      maxContext: 128000,
      supportsToolUse: true,
    ),
  );

  final thinkingChars = <int>[0];
  final sub = provider.thinking().listen(
    (d) => thinkingChars[0] += d.text.length,
  );

  final snapshot = ConversationSnapshot(
    systemMessage:
        'You are a health checker. Run a quick check and report the result '
        "using the report.status tool with status='ok' and a short note.",
    turns: [
      UserTurn(observation: Observation.empty(), diff: ObservationDiff.empty()),
    ],
    tools: [tool],
  );

  final sw = Stopwatch()..start();
  try {
    final decision = await provider.decide(
      snapshot,
      ActionSchema.fromToolList([tool]),
    );
    sw.stop();
    await sub.cancel();
    provider.dispose();

    stdout.writeln(
      '=== SEAM LIVE — swift-infer qwen3.6 (${sw.elapsedMilliseconds}ms) ===',
    );
    stdout.writeln(
      'action.tool       : ${decision.action.tool}  '
      '${decision.action.tool == "report.status" ? "<- PASS (decoded dotted)" : "<- ?"}',
    );
    stdout.writeln('action.args       : ${decision.action.args}');
    stdout.writeln(
      'thinking captured : ${decision.thinking?.length ?? 0} chars',
    );
    stdout.writeln('thinking streamed : ${thinkingChars[0]} chars');
    stdout.writeln('providerRequestId : ${decision.providerRequestId}');
  } on SchemaRejection catch (e) {
    sw.stop();
    await sub.cancel();
    provider.dispose();
    stderr.writeln(
      'SCHEMA REJECTION after ${sw.elapsedMilliseconds}ms: '
      '${e.validationError}\nraw: ${e.rawOutput}',
    );
    exit(1);
  }
}
