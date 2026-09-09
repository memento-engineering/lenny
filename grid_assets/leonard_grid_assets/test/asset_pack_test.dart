import 'dart:io';

import 'package:grid_engine/grid_engine.dart';
import 'package:leonard_grid_assets/leonard_grid_assets.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('the packaged-assets manifest mirrors both Dart circuits', () {
    final YamlMap manifest =
        loadYaml(File('extension/mcp/config.yaml').readAsStringSync())
            as YamlMap;
    final YamlMap pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    expect(manifest['name'], pubspec['name']);
    expect(manifest['name'], 'leonard_grid_assets');
    expect(manifest['resources'], isA<YamlList>());
    expect(manifest['resources'] as YamlList, isEmpty);
    expect(manifest.containsKey('grid'), isFalse);

    final YamlList circuits = manifest['circuits'] as YamlList;
    const List<Circuit> definitions = <Circuit>[kSelfdriveCircuit, kE2eCircuit];
    expect(circuits, hasLength(definitions.length));
    for (final Circuit definition in definitions) {
      final YamlMap circuit = circuits.cast<YamlMap>().singleWhere(
        (YamlMap value) => value['id'] == definition.id,
      );
      expect(circuit['terminal_step'], definition.terminalStepId);
      expect(circuit['supervision'], 'rest_for_one');

      final YamlList manifestSteps = circuit['steps'] as YamlList;
      expect(manifestSteps, hasLength(definition.steps.length));
      for (var index = 0; index < definition.steps.length; index++) {
        final CircuitStep step = definition.steps[index];
        final CapabilityStep capability = switch (step) {
          CapabilityStep() => step,
          SubCircuitStep() => fail(
            '${definition.id} manifest supports only capability steps',
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
    }
  });
}
