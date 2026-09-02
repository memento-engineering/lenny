/// Capability registry composition for Lenny's self-drive assets.
library;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart'
    show ShellRunner, SystemShellRunner, buildCodeRegistry;
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/grid_sdk.dart' show WorkNoteAppender;

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

/// Resolves this pack before falling through to the station's code registry.
class SelfdriveCapabilityRegistry implements CapabilityRegistry {
  /// Composes [pack] over [base].
  const SelfdriveCapabilityRegistry({required this.pack, required this.base});

  /// This pack's registry.
  final CapabilityRegistry pack;

  /// Underlying station registry.
  final CapabilityRegistry base;

  @override
  Circuit? circuit(String circuitId) =>
      pack.circuit(circuitId) ?? base.circuit(circuitId);

  @override
  Seed host(StepMount mount) =>
      kSelfdriveCapabilityIds.contains(mount.step.capabilityId)
      ? pack.host(mount)
      : base.host(mount);

  @override
  DateTime now() => base.now();
}

/// Builds the self-drive registry over the ordinary code registry.
CapabilityRegistry buildSelfdriveRegistry(
  WorkNoteAppender appendNote, {
  HarnessLauncher launcher = launchPanelHarness,
  ServedModelSource models = fetchServedModelIds,
  ShellRunner shell = const SystemShellRunner(),
  CapabilityRegistry? base,
}) => SelfdriveCapabilityRegistry(
  pack: DefaultCapabilityRegistry(
    capabilities: <String, Capability>{
      kSelfdrivePreflightStep: SelfdrivePreflightCapability(models: models),
      kSelfdrivePanelHarnessStep: PanelHarnessCapability(launcher: launcher),
      kSelfdriveOuterDriverStep: const OuterDriverCapability(),
      kSelfdriveVerifyStep: SelfdriveVerifyCapability(
        appendNote: appendNote,
        shell: shell,
      ),
    },
    circuits: const <String, Circuit>{kSelfdriveCircuitId: kSelfdriveCircuit},
  ),
  base: base ?? buildCodeRegistry(),
);
