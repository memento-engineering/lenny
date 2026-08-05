import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  const Set<String> allowedRuntimeDependencies = <String>{
    // lenny-oz64: keep this list closed because a model-stack runtime
    // dependency drags in sse_channel and breaks signalr_netcore
    // co-installation for leonard_flutter consumers.
    'flutter',
    'genesis_perception',
    'leonard_contract',
    'meta',
    'vm_service',
  };

  test('runtime dependencies match the closed allow-list', () {
    final Set<String> actual = _runtimeDependencyNames(
      File('pubspec.yaml').readAsStringSync(),
    );

    expect(
      actual,
      allowedRuntimeDependencies,
      reason: _dependencyDriftMessage(
        actual: actual,
        expected: allowedRuntimeDependencies,
      ),
    );
  });

  test('dependency drift names additions and removals', () {
    expect(
      _dependencyDriftMessage(
        actual: <String>{'flutter', 'leonard_agent'},
        expected: <String>{'flutter', 'vm_service'},
      ),
      'leonard_agent was re-added to leonard_flutter runtime dependencies.\n'
      'vm_service was removed from leonard_flutter runtime dependencies.',
    );
  });

  test('dev dependencies are not part of the runtime set', () {
    const String pubspec = '''
name: example
dependencies:
  flutter:
    sdk: flutter
dev_dependencies:
  flutter_test:
    sdk: flutter
  leonard_agent: ^0.2.0
''';

    expect(_runtimeDependencyNames(pubspec), <String>{'flutter'});
  });
}

Set<String> _runtimeDependencyNames(String source) {
  final YamlMap pubspec = loadYaml(source) as YamlMap;
  final YamlMap dependencies = pubspec['dependencies'] as YamlMap;
  return dependencies.keys.cast<String>().toSet();
}

String _dependencyDriftMessage({
  required Set<String> actual,
  required Set<String> expected,
}) {
  final List<String> additions = actual.difference(expected).toList()..sort();
  final List<String> removals = expected.difference(actual).toList()..sort();
  return <String>[
    for (final String package in additions)
      '$package was re-added to leonard_flutter runtime dependencies.',
    for (final String package in removals)
      '$package was removed from leonard_flutter runtime dependencies.',
  ].join('\n');
}
