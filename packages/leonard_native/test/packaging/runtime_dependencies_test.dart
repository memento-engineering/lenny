import 'dart:io';

import 'package:test/test.dart';

import '../../../leonard_host/test/support/runtime_dependency_guard.dart';

void main() {
  // lenny-oz64: keep this list closed because a model-stack runtime
  // dependency can drag sse_channel into every consumer's resolved graph.
  const Set<String> allowedRuntimeDependencies = <String>{
    'genesis_perception',
    'http',
    'leonard_contract',
    'leonard_host',
    'meta',
    'xml',
  };

  test('runtime dependencies match the closed allow-list', () {
    final Set<String> actual = runtimeDependencyNames(
      File('pubspec.yaml').readAsStringSync(),
    );

    expect(
      actual,
      allowedRuntimeDependencies,
      reason: dependencyDriftMessage(
        package: 'leonard_native',
        actual: actual,
        expected: allowedRuntimeDependencies,
      ),
    );
  });

  test('dependency drift names additions and removals', () {
    expect(
      dependencyDriftMessage(
        package: 'leonard_native',
        actual: <String>{'genesis_perception', 'leonard_agent'},
        expected: <String>{'genesis_perception', 'xml'},
      ),
      'leonard_agent was re-added to leonard_native runtime dependencies.\n'
      'xml was removed from leonard_native runtime dependencies.',
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
