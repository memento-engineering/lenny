/// Spike 5 codegen entry point.
///
/// Reads schema/catalog.json and writes THREE generated projections:
///   - lib/src/generated/registry.g.dart    (typed Dart factory registry,
///     emitted by spike3's generateFromCatalog — A2 reuse)
///   - lib/src/generated/tool_schema.g.json (LLM-facing JSON Schema,
///     augmented with action affordances)
///   - lib/src/generated/actions.g.dart     (catalog-derived action
///     affordance data for the router's hit-test)
///
/// Run from anywhere:
///   dart run spikes/spike5_action_roundtrip/tool/generate.dart
library;

import 'dart:io';

// Relative import (not package:) so this script runs under any package
// config, including the repo-root workspace config which does not include
// this spike package.
import '../lib/src/generator.dart';

void main() {
  final packageRoot = _findPackageRoot();
  final catalogFile = File('$packageRoot/schema/catalog.json');
  final outputs = generateSpike5(catalogFile.readAsStringSync());

  final generatedDir = Directory('$packageRoot/lib/src/generated')
    ..createSync(recursive: true);
  final registryFile = File('${generatedDir.path}/registry.g.dart')
    ..writeAsStringSync(outputs.registryDart);
  final schemaFile = File('${generatedDir.path}/tool_schema.g.json')
    ..writeAsStringSync(outputs.toolSchemaJson);
  final actionsFile = File('${generatedDir.path}/actions.g.dart')
    ..writeAsStringSync(outputs.actionsDart);

  stdout
    ..writeln('generated ${registryFile.path}')
    ..writeln('generated ${schemaFile.path}')
    ..writeln('generated ${actionsFile.path}');
}

String _findPackageRoot() {
  final candidates = <String>[
    // Platform.script -> .../spike5_action_roundtrip/tool/generate.dart
    File.fromUri(Platform.script).parent.parent.path,
    // cwd == package root
    Directory.current.path,
    // cwd == repo root
    '${Directory.current.path}/spikes/spike5_action_roundtrip',
  ];
  for (final c in candidates) {
    if (File('$c/schema/catalog.json').existsSync()) return c;
  }
  throw StateError(
    'could not locate spike5_action_roundtrip/schema/catalog.json '
    '(tried: $candidates)',
  );
}
