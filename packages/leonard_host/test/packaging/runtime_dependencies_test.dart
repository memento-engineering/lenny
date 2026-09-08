import 'dart:io';

import 'package:test/test.dart';

import '../support/runtime_dependency_guard.dart';

void main() {
  // lenny-oz64: keep this list closed because a model-stack runtime
  // dependency can drag sse_channel into every consumer's resolved graph.
  const Set<String> allowedRuntimeDependencies = <String>{
    'genesis_perception',
    'leonard_contract',
  };

  test('runtime dependencies match the closed allow-list', () {
    final Set<String> actual = runtimeDependencyNames(
      File('pubspec.yaml').readAsStringSync(),
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

  test('dependency drift names additions and removals', () {
    expect(
      dependencyDriftMessage(
        package: 'leonard_host',
        actual: <String>{'genesis_perception', 'leonard_agent'},
        expected: <String>{'genesis_perception', 'leonard_contract'},
      ),
      'leonard_agent was re-added to leonard_host runtime dependencies.\n'
      'leonard_contract was removed from leonard_host runtime dependencies.',
    );
  });

  test('dev dependencies are not part of the runtime set', () {
    const String pubspec = '''
name: example
dependencies:
  genesis_perception: ^0.3.0
dev_dependencies:
  leonard_agent: ^0.2.0
''';

    expect(runtimeDependencyNames(pubspec), <String>{'genesis_perception'});
  });
}
