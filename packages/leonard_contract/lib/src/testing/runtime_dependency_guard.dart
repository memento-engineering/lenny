/// The runtime (non-dev) dependency names of a parsed pubspec.
///
/// Takes the already-parsed document (a `YamlMap` is a `Map`) so this
/// package needs no YAML parser of its own.
Set<String> runtimeDependencyNames(Map<Object?, Object?> pubspec) {
  final Object? dependencies = pubspec['dependencies'];
  if (dependencies is! Map) return <String>{};
  return dependencies.keys.cast<String>().toSet();
}

/// Explains how [actual] drifted from [expected], one sorted line per
/// re-added or removed dependency of [package]. Empty when they match.
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
