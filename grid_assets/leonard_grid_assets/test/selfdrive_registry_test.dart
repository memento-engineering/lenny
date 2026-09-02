import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:leonard_grid_assets/leonard_grid_assets.dart';
import 'package:test/test.dart';

StepMount _mount(CapabilityStep step) => StepMount(
  step: step,
  nodePath: 'work/selfdrive/${step.stepId}',
  circuit: kSelfdriveCircuit,
  circuitPath: 'work/selfdrive',
  session: const SessionHandle('session'),
  node: const NodeCursor(),
  key: ValueKey<String>('work/selfdrive/${step.stepId}#0.0'),
);

void main() {
  test('the pack circuit composes over the code registry', () {
    final CapabilityRegistry registry = buildSelfdriveRegistry(
      (String _, String __) async {},
    );
    expect(registry.circuit(kSelfdriveCircuitId), same(kSelfdriveCircuit));
    expect(registry.circuit('code'), isNotNull);
    expect(registry.circuit('nope'), isNull);
  });

  test(
    'all four circuit capability ids resolve to the pack implementations',
    () {
      final CapabilityRegistry registry = buildSelfdriveRegistry(
        (String _, String __) async {},
      );
      final Map<String, Type> expected = <String, Type>{
        kSelfdrivePreflightStep: SelfdrivePreflightCapability,
        kSelfdrivePanelHarnessStep: PanelHarnessCapability,
        kSelfdriveOuterDriverStep: OuterDriverCapability,
        kSelfdriveVerifyStep: SelfdriveVerifyCapability,
      };
      final List<CapabilityStep> steps = kSelfdriveCircuit.steps
          .whereType<CapabilityStep>()
          .toList(growable: false);
      expect(
        steps.map((CapabilityStep step) => step.capabilityId).toSet(),
        kSelfdriveCapabilityIds,
      );
      for (final CapabilityStep step in steps) {
        final Seed host = registry.host(_mount(step));
        expect(host, isA<CapabilityHost>(), reason: step.capabilityId);
        expect(
          (host as CapabilityHost).capability.runtimeType,
          expected[step.capabilityId],
          reason: step.capabilityId,
        );
      }
    },
  );
}
