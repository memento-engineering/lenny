import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:leonard_grid_assets/leonard_grid_assets.dart';
import 'package:test/test.dart';

const Map<String, dynamic> _required = <String, dynamic>{
  kE2eGoalKey: 'open settings',
  kE2eAppDirKey: '/repo/app',
};

Bead _bead(Map<String, dynamic> metadata) =>
    Bead(id: 'e2e-work', metadata: metadata);

void main() {
  test('E2eOrder applies Command defaults', () {
    final E2eOrder order = E2eOrder.fromBead(_bead(_required))!;
    expect(order.request.model, E2eModel.claude);
    expect(order.request.extensions, <String>['router', 'riverpod', 'dio']);
    expect(order.request.cliPrefix, <String>['dart', 'run', 'leonard_cli']);
    expect(order.request.device, isNull);
  });

  test('E2eOrder maps every optional field', () {
    final E2eOrder order = E2eOrder.fromBead(
      _bead(<String, dynamic>{
        ..._required,
        kE2eModelKey: 'qwen-mlx',
        kE2eModelIdKey: 'model',
        kE2eDeviceKey: 'ios',
        kE2eExtensionsKey: 'router,dio',
        kE2eCliKey: "dart run 'driver.dart'",
        kE2eDoneReasonPatternKey: 'reason',
        kE2eDoneEvidencePatternKey: 'evidence',
        kE2eExpectRouteKey: 'settings',
        kE2eExpectLabelKey: 'Dark Theme',
        kE2eExpectStateKey: 'on',
      }),
    )!;
    expect(order.request.model, E2eModel.qwenMlx);
    expect(order.request.modelId, 'model');
    expect(order.request.device, 'ios');
    expect(order.request.extensions, <String>['router', 'dio']);
    expect(order.request.cliPrefix, <String>['dart', 'run', 'driver.dart']);
    expect(order.request.doneReasonPattern, 'reason');
    expect(order.request.doneEvidencePattern, 'evidence');
    expect(order.request.expectation.route, 'settings');
    expect(order.request.expectation.semanticsLabel, 'Dark Theme');
    expect(order.request.expectation.semanticsState, 'on');
  });

  test('e2eCircuitFor fails closed on incomplete and invalid orders', () {
    expect(e2eCircuitFor(_bead(_required)), same(kE2eCircuit));
    for (final Map<String, dynamic> invalid in <Map<String, dynamic>>[
      <String, dynamic>{kE2eAppDirKey: '/repo/app'},
      <String, dynamic>{kE2eGoalKey: 'goal'},
      <String, dynamic>{..._required, kE2eAppDirKey: 'relative'},
      <String, dynamic>{..._required, kE2eModelKey: 'other'},
      <String, dynamic>{..._required, kE2eExpectLabelKey: 'Toggle'},
      <String, dynamic>{..._required, kE2eExpectStateKey: 'on'},
      <String, dynamic>{..._required, kE2eCliKey: "'unterminated"},
    ]) {
      expect(e2eCircuitFor(_bead(invalid)), isNull, reason: '$invalid');
    }
  });

  test('circuit has the pinned supervised four-phase shape', () {
    expect(kE2eCircuit.id, kE2eCircuitId);
    expect(kE2eCircuit.terminalStepId, kE2eInspectStep);
    expect(kE2eCircuit.supervision, SupervisionStrategy.restForOne);
    expect(kE2eCircuit.backoff, Backoff.standard);
    expect(kE2eCircuit.maxRestarts, 3);

    final List<CapabilityStep> steps = kE2eCircuit.steps
        .whereType<CapabilityStep>()
        .toList(growable: false);
    expect(steps.map((CapabilityStep step) => step.stepId), <String>[
      kE2ePreflightStep,
      kE2eLaunchStep,
      kE2eRunStep,
      kE2eInspectStep,
    ]);
    expect(steps.map((CapabilityStep step) => step.capabilityId), <String>[
      kE2ePreflightCapabilityId,
      kE2eLaunchCapabilityId,
      kE2eRunCapabilityId,
      kE2eInspectCapabilityId,
    ]);
    expect(steps[0].kind, StepKind.job);
    expect(steps[0].dependsOn, isEmpty);
    expect(steps[1].kind, StepKind.daemon);
    expect(steps[1].dependsOn, <String>{kE2ePreflightStep});
    expect(steps[2].dependsOn, <String>{kE2eLaunchStep});
    expect(steps[3].dependsOn, <String>{kE2eRunStep});
  });
}
