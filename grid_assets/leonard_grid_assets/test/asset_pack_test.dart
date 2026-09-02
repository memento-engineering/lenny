import 'dart:io';

import 'package:grid_engine/grid_engine.dart';
import 'package:leonard_grid_assets/leonard_grid_assets.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('the packaged-assets manifest mirrors the Dart circuit', () {
    final YamlMap manifest =
        loadYaml(File('extension/mcp/config.yaml').readAsStringSync())
            as YamlMap;
    final YamlMap pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    expect(manifest['name'], pubspec['name']);
    expect(manifest['name'], 'leonard_grid_assets');
    expect(manifest['resources'], isA<YamlList>());
    expect(manifest['resources'] as YamlList, isEmpty);

    final YamlList circuits = manifest['circuits'] as YamlList;
    expect(circuits, hasLength(1));
    final YamlMap circuit = circuits.single as YamlMap;
    expect(circuit['id'], kSelfdriveCircuit.id);
    expect(circuit['terminal_step'], kSelfdriveCircuit.terminalStepId);
    expect(circuit['supervision'], 'rest_for_one');

    final YamlList manifestSteps = circuit['steps'] as YamlList;
    expect(manifestSteps, hasLength(kSelfdriveCircuit.steps.length));
    for (var index = 0; index < kSelfdriveCircuit.steps.length; index++) {
      final CircuitStep step = kSelfdriveCircuit.steps[index];
      final CapabilityStep capability = switch (step) {
        CapabilityStep() => step,
        SubCircuitStep() => fail(
          'selfdrive manifest supports only capability steps',
        ),
      };
      final YamlMap actual = manifestSteps[index] as YamlMap;
      expect(actual['id'], capability.stepId);
      expect(actual['capability'], capability.capabilityId);
      expect(actual['kind'], switch (capability.kind) {
        StepKind.job => 'job',
        StepKind.daemon => 'daemon',
      });
      expect(
        (actual['depends_on'] as YamlList)
            .map((Object? value) => value as String)
            .toSet(),
        capability.dependsOn,
      );
    }
  });
}
