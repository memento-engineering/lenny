import 'dart:io';

import 'package:leonard_contract/testing.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  // lenny-oz64: keep this list closed because a model-stack runtime
  // dependency can drag sse_channel into every consumer's resolved graph.
  const Set<String> allowedRuntimeDependencies = <String>{
    'genesis_perception',
    'leonard_contract',
  };

  test('runtime dependencies match the closed allow-list', () {
    final Set<String> actual = runtimeDependencyNames(
      loadYaml(File('pubspec.yaml').readAsStringSync())
          as Map<Object?, Object?>,
    );

    expect(
      actual,
      allowedRuntimeDependencies,
      reason: dependencyDriftMessage(
        package: 'leonard_host',
        actual: actual,
        expected: allowedRuntimeDependencies,
      ),
    );
  });
}
