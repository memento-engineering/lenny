import 'dart:io';

import 'package:leonard_contract/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  // lenny-oz64: keep this list closed because a model-stack runtime
  // dependency drags in sse_channel and breaks signalr_netcore
  // co-installation for leonard_flutter consumers.
  const Set<String> allowedRuntimeDependencies = <String>{
    'flutter',
    'genesis_perception',
    'leonard_contract',
    'meta',
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
        package: 'leonard_flutter',
        actual: actual,
        expected: allowedRuntimeDependencies,
      ),
    );
  });
}
