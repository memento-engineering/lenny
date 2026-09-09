import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/grid_sdk.dart' show WorkNoteAppender;
import 'package:leonard_grid_assets/leonard_grid_assets.dart';
import 'package:test/test.dart';

class _StationStandIn {
  Circuit? circuitOverrideFor(Bead bead) => selfdriveCircuitFor(bead);

  CapabilityRegistry buildWorkRegistry(WorkNoteAppender appendNote) =>
      buildSelfdriveRegistry(appendNote);
}

void main() {
  test('a selfdrive-marked bead rides both station work-policy hooks', () {
    final _StationStandIn station = _StationStandIn();
    const Bead marked = Bead(
      id: 'lenny-selfdrive-1',
      metadata: <String, dynamic>{
        kSelfdriveScenarioKey:
            'packages/leonard_cli/scenarios/leonard_devtools_panel.md',
        kSelfdriveOuterModelKey: 'qwen3.6-35b-a3b-8bit',
        kSelfdriveInnerModelKey: 'qwen3.6-35b-a3b-8bit',
      },
    );
    expect(station.circuitOverrideFor(marked), same(kSelfdriveCircuit));
    expect(station.circuitOverrideFor(const Bead(id: 'lenny-code')), isNull);

    final CapabilityRegistry registry = station.buildWorkRegistry(
      (String _, String __) async {},
    );
    expect(registry.circuit(kSelfdriveCircuitId), same(kSelfdriveCircuit));
    expect(registry.circuit('code'), isNotNull);
  });

  test('the Command and both circuits coexist over the code registry', () {
    final E2eCommand command = E2eCommand(
      out: StringBuffer(),
      err: StringBuffer(),
    );
    expect(command.name, 'e2e');

    final CapabilityRegistry registry = buildLeonardRegistry(
      (String _, String __) async {},
    );
    expect(registry.circuit(kSelfdriveCircuitId), same(kSelfdriveCircuit));
    expect(registry.circuit(kE2eCircuitId), same(kE2eCircuit));
    expect(registry.circuit('code'), isNotNull);
  });
}
