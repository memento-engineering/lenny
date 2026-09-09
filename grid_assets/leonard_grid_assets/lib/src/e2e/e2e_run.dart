/// Leonard child-process invocation and receipt data.
library;

import 'package:path/path.dart' as p;

import 'e2e_service.dart';
import 'e2e_session.dart';

/// Receipt from invoking the outer Leonard driver.
class E2eRunReceipt {
  /// Creates a child-process receipt.
  const E2eRunReceipt({
    required this.trajectoryPath,
    required this.driverExitStatus,
    required this.stdout,
    required this.stderr,
  });

  /// Explicit trajectory JSONL path supplied to Leonard.
  final String trajectoryPath;

  /// Leonard child-process exit status. This is data, not the verdict.
  final int driverExitStatus;

  /// Captured standard output, retained only for diagnostics.
  final String stdout;

  /// Captured standard error, retained only for diagnostics.
  final String stderr;
}

/// Invokes Leonard with an explicit trajectory and preserves its exit status.
Future<E2eRunReceipt> performE2eRun(
  E2eRuntime runtime,
  E2eSessionRequest request, {
  required Uri vmUri,
  required String runDir,
  String? resolvedModelId,
}) async {
  if (request.cliPrefix.isEmpty) {
    throw const E2ePhaseFailure(
      E2eFailureCode.invalidRequest,
      'e2e run refused: CLI prefix is empty',
    );
  }
  final String trajectoryPath = p.join(runDir, 'trajectory.jsonl');
  final List<String> argv = <String>[
    ...request.cliPrefix.skip(1),
    '--vm-uri',
    vmUri.toString(),
    '--goal',
    request.goal,
    '--extensions',
    request.extensions.join(','),
    '--model',
    request.model.cliName,
    '--policy',
    'action-relative',
    '--output',
    trajectoryPath,
    if (resolvedModelId != null && resolvedModelId.isNotEmpty) ...<String>[
      '--model-id',
      resolvedModelId,
    ],
    if (request.doneReasonPattern != null) ...<String>[
      '--done-reason-pattern',
      request.doneReasonPattern!,
    ],
    if (request.doneEvidencePattern != null) ...<String>[
      '--done-evidence-pattern',
      request.doneEvidencePattern!,
    ],
  ];
  final E2eProcessResult result = await runtime.runProcess(
    request.cliPrefix.first,
    argv,
  );
  return E2eRunReceipt(
    trajectoryPath: trajectoryPath,
    driverExitStatus: result.exitCode,
    stdout: result.stdout,
    stderr: result.stderr,
  );
}
