/// The four deterministic phases as one station-driven circuit.
library;

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:path/path.dart' as p;

import 'e2e_session.dart';

/// Circuit id and registry key.
const String kE2eCircuitId = 'leonard-e2e';

/// Preflight circuit step id.
const String kE2ePreflightStep = 'preflight';

/// Launch circuit step id.
const String kE2eLaunchStep = 'launch';

/// Run circuit step id.
const String kE2eRunStep = 'run';

/// Terminal inspect circuit step id.
const String kE2eInspectStep = 'inspect';

/// Preflight capability id.
const String kE2ePreflightCapabilityId = 'e2e-preflight';

/// Launch capability id.
const String kE2eLaunchCapabilityId = 'e2e-launch';

/// Run capability id.
const String kE2eRunCapabilityId = 'e2e-run';

/// Inspect capability id.
const String kE2eInspectCapabilityId = 'e2e-inspect';

/// Required goal metadata key.
const String kE2eGoalKey = 'e2e.goal';

/// Required absolute application directory metadata key.
const String kE2eAppDirKey = 'e2e.app_dir';

/// Optional provider tier metadata key.
const String kE2eModelKey = 'e2e.model';

/// Optional exact model id metadata key.
const String kE2eModelIdKey = 'e2e.model_id';

/// Optional device metadata key.
const String kE2eDeviceKey = 'e2e.device';

/// Optional comma-separated extensions metadata key.
const String kE2eExtensionsKey = 'e2e.extensions';

/// Optional CLI prefix metadata key.
const String kE2eCliKey = 'e2e.cli';

/// Optional done-reason pattern metadata key.
const String kE2eDoneReasonPatternKey = 'e2e.done_reason_pattern';

/// Optional done-evidence pattern metadata key.
const String kE2eDoneEvidencePatternKey = 'e2e.done_evidence_pattern';

/// Optional final route metadata key.
const String kE2eExpectRouteKey = 'e2e.expect_route';

/// Optional final semantics label metadata key.
const String kE2eExpectLabelKey = 'e2e.expect_label';

/// Optional final semantics state metadata key.
const String kE2eExpectStateKey = 'e2e.expect_state';

/// Result key carrying the selected device.
const String kE2eDeviceResultKey = 'E2E_DEVICE';

/// Result key carrying the exact resolved model id.
const String kE2eModelIdResultKey = 'E2E_MODEL_ID';

/// Result key carrying the Flutter VM-service URI.
const String kE2eVmUriResultKey = 'E2E_VM_URI';

/// Result key carrying the artifact directory.
const String kE2eRunDirResultKey = 'E2E_RUN_DIR';

/// Result key carrying the trajectory path.
const String kE2eTrajectoryResultKey = 'E2E_TRAJECTORY';

/// Result key carrying the decimal Leonard exit status.
const String kE2eDriverStatusResultKey = 'E2E_DRIVER_STATUS';

/// Result key carrying the terminal structured verdict.
const String kE2eVerdictJsonResultKey = 'E2E_VERDICT_JSON';

/// Preflight → launch → run → inspect.
const Circuit kE2eCircuit = Circuit(
  id: kE2eCircuitId,
  terminalStepId: kE2eInspectStep,
  supervision: SupervisionStrategy.restForOne,
  steps: <CircuitStep>[
    CapabilityStep(
      stepId: kE2ePreflightStep,
      capabilityId: kE2ePreflightCapabilityId,
    ),
    CapabilityStep(
      stepId: kE2eLaunchStep,
      capabilityId: kE2eLaunchCapabilityId,
      kind: StepKind.daemon,
      dependsOn: <String>{kE2ePreflightStep},
    ),
    CapabilityStep(
      stepId: kE2eRunStep,
      capabilityId: kE2eRunCapabilityId,
      dependsOn: <String>{kE2eLaunchStep},
    ),
    CapabilityStep(
      stepId: kE2eInspectStep,
      capabilityId: kE2eInspectCapabilityId,
      dependsOn: <String>{kE2eRunStep},
    ),
  ],
);

/// A validated E2E order decoded from bead metadata.
class E2eOrder {
  /// Creates an order around its reusable request.
  const E2eOrder(this.request);

  /// Decodes an order, failing closed on missing or invalid values.
  static E2eOrder? fromBead(Bead bead) {
    final String goal = _string(bead, kE2eGoalKey);
    final String appDir = _string(bead, kE2eAppDirKey);
    if (goal.isEmpty || appDir.isEmpty || !p.isAbsolute(appDir)) return null;

    final String modelValue = _string(bead, kE2eModelKey);
    final E2eModel? model = E2eModel.tryParse(
      modelValue.isEmpty ? E2eModel.claude.cliName : modelValue,
    );
    if (model == null) return null;
    final String extensionValue = _string(bead, kE2eExtensionsKey);
    final List<String> extensions =
        (extensionValue.isEmpty ? 'router,riverpod,dio' : extensionValue)
            .split(',')
            .map((String value) => value.trim())
            .where((String value) => value.isNotEmpty)
            .toList(growable: false);
    if (extensions.isEmpty) return null;
    final String cliValue = _string(bead, kE2eCliKey);
    final List<String> cliPrefix;
    try {
      cliPrefix = parseE2eCliPrefix(
        cliValue.isEmpty ? 'dart run leonard_cli' : cliValue,
      );
    } on FormatException {
      return null;
    }
    if (cliPrefix.isEmpty) return null;
    final String label = _string(bead, kE2eExpectLabelKey);
    final String state = _string(bead, kE2eExpectStateKey);
    if (label.isEmpty != state.isEmpty) return null;

    String? optional(String key) {
      final String value = _string(bead, key);
      return value.isEmpty ? null : value;
    }

    return E2eOrder(
      E2eSessionRequest(
        goal: goal,
        appDir: appDir,
        model: model,
        modelId: optional(kE2eModelIdKey),
        device: optional(kE2eDeviceKey),
        extensions: extensions,
        cliPrefix: cliPrefix,
        doneReasonPattern: optional(kE2eDoneReasonPatternKey),
        doneEvidencePattern: optional(kE2eDoneEvidencePatternKey),
        expectation: E2eObservationExpectation(
          route: optional(kE2eExpectRouteKey),
          semanticsLabel: label.isEmpty ? null : label,
          semanticsState: state.isEmpty ? null : state,
        ),
      ),
    );
  }

  static String _string(Bead bead, String key) {
    final Object? value = bead.metadata[key];
    return value is String ? value.trim() : '';
  }

  /// Reusable typed session request.
  final E2eSessionRequest request;
}

/// Returns the E2E circuit only for a complete, valid E2E order.
Circuit? e2eCircuitFor(Bead bead) =>
    E2eOrder.fromBead(bead) == null ? null : kE2eCircuit;
