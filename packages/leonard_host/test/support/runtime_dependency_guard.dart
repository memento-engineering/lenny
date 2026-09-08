import 'package:yaml/yaml.dart';

/// Returns the names in the manifest's top-level runtime dependency map.
Set<String> runtimeDependencyNames(String pubspecSource) {
  final YamlMap pubspec = loadYaml(pubspecSource) as YamlMap;
  final YamlMap dependencies = pubspec['dependencies'] as YamlMap;
  return dependencies.keys.cast<String>().toSet();
}

/// Describes unexpected additions before unexpected removals, sorted by name.
String dependencyDriftMessage({
  required String package,
  required Set<String> actual,
  required Set<String> expected,
}) {
  final List<String> additions = actual.difference(expected).toList()..sort();
  final List<String> removals = expected.difference(actual).toList()..sort();
  return <String>[
    for (final String dependency in additions)
      '$dependency was re-added to $package runtime dependencies.',
    for (final String dependency in removals)
      '$dependency was removed from $package runtime dependencies.',
  ].join('\n');
}
