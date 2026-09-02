/// The station-driven `selfdrive` circuit and its bead-keyed order.
library;

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';

/// The circuit id, also used as its registry key.
const String kSelfdriveCircuitId = 'selfdrive';

/// Resolves and pins both model ids before any process starts.
const String kSelfdrivePreflightStep = 'preflight';

/// The long-lived panel and sample-app harness.
const String kSelfdrivePanelHarnessStep = 'panel-harness';

/// The outer `leonard_cli` driver.
const String kSelfdriveOuterDriverStep = 'outer-driver';

/// The terminal receipt verifier.
const String kSelfdriveVerifyStep = 'verify';

/// Bead metadata key for the scenario path.
const String kSelfdriveScenarioKey = 'selfdrive.scenario';

/// Bead metadata key for the outer model id.
const String kSelfdriveOuterModelKey = 'selfdrive.outer_model';

/// Bead metadata key for the inner model id.
const String kSelfdriveInnerModelKey = 'selfdrive.inner_model';

/// Optional bead metadata key for the sample-app device.
const String kSelfdriveDeviceKey = 'selfdrive.device';

/// Result key under which the harness publishes its run directory.
const String kSelfdriveRunDirKey = 'SELFDRIVE_RUN_DIR';

/// Result key under which the driver publishes its trajectory.
const String kSelfdriveTrajectoryKey = 'SELFDRIVE_TRAJECTORY';

/// The four URI publications required for harness readiness.
const List<String> kSelfdriveUriKeys = <String>[
  'SAMPLE_APP_VM_URI',
  'DTD_URI',
  'PANEL_URL',
  'PANEL_DWDS_URI',
];

/// The panel endpoint consumed by the outer driver.
const String kPanelDwdsUriKey = 'PANEL_DWDS_URI';

/// Preflight → panel-harness → outer-driver → verify.
///
/// `restForOne` keeps the harness and everything bound to its endpoints in the
/// same restart suffix. The engine's mandatory standard backoff and
/// three-restart circuit-breaker defaults are intentionally retained.
const Circuit kSelfdriveCircuit = Circuit(
  id: kSelfdriveCircuitId,
  terminalStepId: kSelfdriveVerifyStep,
  supervision: SupervisionStrategy.restForOne,
  steps: <CircuitStep>[
    CapabilityStep(
      stepId: kSelfdrivePreflightStep,
      capabilityId: kSelfdrivePreflightStep,
    ),
    CapabilityStep(
      stepId: kSelfdrivePanelHarnessStep,
      capabilityId: kSelfdrivePanelHarnessStep,
      kind: StepKind.daemon,
      dependsOn: <String>{kSelfdrivePreflightStep},
    ),
    CapabilityStep(
      stepId: kSelfdriveOuterDriverStep,
      capabilityId: kSelfdriveOuterDriverStep,
      dependsOn: <String>{kSelfdrivePanelHarnessStep},
    ),
    CapabilityStep(
      stepId: kSelfdriveVerifyStep,
      capabilityId: kSelfdriveVerifyStep,
      dependsOn: <String>{kSelfdriveOuterDriverStep},
    ),
  ],
);

/// A self-drive order decoded as a value from a work bead.
class SelfdriveOrder {
  /// Creates an order over its decoded values.
  const SelfdriveOrder({
    required this.scenario,
    required this.outerModelId,
    required this.innerModelId,
    required this.device,
  });

  /// Decodes [bead], failing closed when any required key is incomplete.
  static SelfdriveOrder? fromBead(Bead bead) {
    final String scenario = _string(bead, kSelfdriveScenarioKey);
    final String outer = _string(bead, kSelfdriveOuterModelKey);
    final String inner = _string(bead, kSelfdriveInnerModelKey);
    if (scenario.isEmpty || outer.isEmpty || inner.isEmpty) return null;
    final String device = _string(bead, kSelfdriveDeviceKey);
    return SelfdriveOrder(
      scenario: scenario,
      outerModelId: outer,
      innerModelId: inner,
      device: device.isEmpty ? 'macos' : device,
    );
  }

  static String _string(Bead bead, String key) {
    final Object? value = bead.metadata[key];
    return value is String ? value.trim() : '';
  }

  /// Scenario file relative to the workspace root.
  final String scenario;

  /// Requested outer model id.
  final String outerModelId;

  /// Requested inner model id.
  final String innerModelId;

  /// Sample-app device id.
  final String device;
}

/// Returns the self-drive circuit only for a complete self-drive order.
Circuit? selfdriveCircuitFor(Bead bead) =>
    SelfdriveOrder.fromBead(bead) == null ? null : kSelfdriveCircuit;
