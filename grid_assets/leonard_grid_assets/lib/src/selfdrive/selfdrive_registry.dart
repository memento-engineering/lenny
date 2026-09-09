/// Capability registry composition for all Lenny assets.
library;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart'
    show ShellRunner, SystemShellRunner, buildCodeRegistry;
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/grid_sdk.dart' show WorkNoteAppender;

import '../e2e/e2e_capabilities.dart';
import '../e2e/e2e_circuit.dart';
import '../e2e/e2e_service.dart';
import 'outer_driver.dart';
import 'panel_harness.dart';
import 'selfdrive_circuit.dart';
import 'selfdrive_preflight.dart';
import 'selfdrive_verify.dart';

/// Capability ids owned by this pack.
const Set<String> kSelfdriveCapabilityIds = <String>{
  kSelfdrivePreflightStep,
  kSelfdrivePanelHarnessStep,
  kSelfdriveOuterDriverStep,
  kSelfdriveVerifyStep,
};

/// All capability ids owned by this pack.
const Set<String> kLeonardCapabilityIds = <String>{
  ...kSelfdriveCapabilityIds,
  kE2ePreflightCapabilityId,
  kE2eLaunchCapabilityId,
  kE2eRunCapabilityId,
  kE2eInspectCapabilityId,
};

/// Resolves this pack before falling through to the station's code registry.
class LeonardCapabilityRegistry implements CapabilityRegistry {
  /// Composes [pack] over [base].
  const LeonardCapabilityRegistry({required this.pack, required this.base});

  /// This pack's registry.
  final CapabilityRegistry pack;

  /// Underlying station registry.
  final CapabilityRegistry base;

  @override
  Circuit? circuit(String circuitId) =>
      pack.circuit(circuitId) ?? base.circuit(circuitId);

  @override
  Seed host(StepMount mount) =>
      kLeonardCapabilityIds.contains(mount.step.capabilityId)
      ? pack.host(mount)
      : base.host(mount);

  @override
  DateTime now() => base.now();
}

/// Compatibility name for callers that previously composed only selfdrive.
typedef SelfdriveCapabilityRegistry = LeonardCapabilityRegistry;

/// Builds the complete Leonard registry over the ordinary code registry.
CapabilityRegistry buildLeonardRegistry(
  WorkNoteAppender appendNote, {
  HarnessLauncher launcher = launchPanelHarness,
  ServedModelSource models = fetchServedModelIds,
  ShellRunner shell = const SystemShellRunner(),
  E2eService? e2eService,
  CapabilityRegistry? base,
}) {
  final E2eService service = e2eService ?? const E2eService(SystemE2eRuntime());
  return LeonardCapabilityRegistry(
    pack: DefaultCapabilityRegistry(
      capabilities: <String, Capability>{
        kSelfdrivePreflightStep: SelfdrivePreflightCapability(models: models),
        kSelfdrivePanelHarnessStep: PanelHarnessCapability(launcher: launcher),
        kSelfdriveOuterDriverStep: const OuterDriverCapability(),
        kSelfdriveVerifyStep: SelfdriveVerifyCapability(
          appendNote: appendNote,
          shell: shell,
        ),
        kE2ePreflightCapabilityId: E2ePreflightCapability(service),
        kE2eLaunchCapabilityId: E2eLaunchCapability(service),
        kE2eRunCapabilityId: E2eRunCapability(service),
        kE2eInspectCapabilityId: E2eInspectCapability(service),
      },
      circuits: const <String, Circuit>{
        kSelfdriveCircuitId: kSelfdriveCircuit,
        kE2eCircuitId: kE2eCircuit,
      },
    ),
    base: base ?? buildCodeRegistry(),
  );
}

/// Builds the pack registry under its original selfdrive entry point.
CapabilityRegistry buildSelfdriveRegistry(
  WorkNoteAppender appendNote, {
  HarnessLauncher launcher = launchPanelHarness,
  ServedModelSource models = fetchServedModelIds,
  ShellRunner shell = const SystemShellRunner(),
  CapabilityRegistry? base,
}) => buildLeonardRegistry(
  appendNote,
  launcher: launcher,
  models: models,
  shell: shell,
  base: base,
);
