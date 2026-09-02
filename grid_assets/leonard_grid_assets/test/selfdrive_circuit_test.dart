import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:leonard_grid_assets/leonard_grid_assets.dart';
import 'package:test/test.dart';

const Map<String, dynamic> _completeMetadata = <String, dynamic>{
  kSelfdriveScenarioKey:
      'packages/leonard_cli/scenarios/leonard_devtools_panel.md',
  kSelfdriveOuterModelKey: 'qwen3.6-35b-a3b-8bit',
  kSelfdriveInnerModelKey: 'qwen3.6-35b-a3b-8bit',
};

Bead _bead(Map<String, dynamic> metadata) =>
    Bead(id: 'lenny-selfdrive', metadata: metadata);

void main() {
  group('selfdriveCircuitFor', () {
    test('returns the circuit for all three required metadata keys', () {
      expect(
        selfdriveCircuitFor(_bead(_completeMetadata)),
        same(kSelfdriveCircuit),
      );
    });

    for (final String key in <String>[
      kSelfdriveScenarioKey,
      kSelfdriveOuterModelKey,
      kSelfdriveInnerModelKey,
    ]) {
      test('returns null when $key is missing, blank, or non-string', () {
        expect(
          selfdriveCircuitFor(
            _bead(<String, dynamic>{..._completeMetadata}..remove(key)),
          ),
          isNull,
        );
        expect(
          selfdriveCircuitFor(
            _bead(<String, dynamic>{..._completeMetadata, key: '  '}),
          ),
          isNull,
        );
        expect(
          selfdriveCircuitFor(
            _bead(<String, dynamic>{..._completeMetadata, key: 42}),
          ),
          isNull,
        );
      });
    }
  });

  test('SelfdriveOrder defaults and overrides the device', () {
    final SelfdriveOrder defaulted = SelfdriveOrder.fromBead(
      _bead(_completeMetadata),
    )!;
    expect(defaulted.device, 'macos');
    expect(defaulted.scenario, _completeMetadata[kSelfdriveScenarioKey]);

    final SelfdriveOrder explicit = SelfdriveOrder.fromBead(
      _bead(<String, dynamic>{
        ..._completeMetadata,
        kSelfdriveDeviceKey: 'ios-simulator',
      }),
    )!;
    expect(explicit.device, 'ios-simulator');
  });

  test('the circuit has the pinned four-step supervised shape', () {
    expect(kSelfdriveCircuit.id, kSelfdriveCircuitId);
    expect(kSelfdriveCircuit.terminalStepId, kSelfdriveVerifyStep);
    expect(kSelfdriveCircuit.supervision, SupervisionStrategy.restForOne);
    expect(kSelfdriveCircuit.backoff, Backoff.standard);
    expect(kSelfdriveCircuit.maxRestarts, 3);

    final List<CapabilityStep> steps = kSelfdriveCircuit.steps
        .whereType<CapabilityStep>()
        .toList(growable: false);
    expect(steps, hasLength(4));
    expect(steps.map((CapabilityStep step) => step.stepId), <String>[
      kSelfdrivePreflightStep,
      kSelfdrivePanelHarnessStep,
      kSelfdriveOuterDriverStep,
      kSelfdriveVerifyStep,
    ]);
    expect(steps[0].kind, StepKind.job);
    expect(steps[0].dependsOn, isEmpty);
    expect(steps[1].kind, StepKind.daemon);
    expect(steps[1].dependsOn, <String>{kSelfdrivePreflightStep});
    expect(steps[2].kind, StepKind.job);
    expect(steps[2].dependsOn, <String>{kSelfdrivePanelHarnessStep});
    expect(steps[3].kind, StepKind.job);
    expect(steps[3].dependsOn, <String>{kSelfdriveOuterDriverStep});
  });
}
