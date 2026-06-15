/// Spike 3 codegen entry point.
///
/// Reads schema/catalog.json and writes BOTH generated projections:
///   - lib/src/generated/registry.g.dart   (typed Dart factory registry)
///   - lib/src/generated/tool_schema.g.json (LLM-facing JSON Schema)
///
/// Deliberately a plain `dart run` script for the spike; production codegen
/// will be a build_runner builder (genesis A6). The core is importable
/// (../lib/src/generator.dart) so tests can re-run it in memory and prove
/// the on-disk artifacts are in sync with the catalog.
///
/// Run from anywhere; it locates the package root via Platform.script with
/// cwd-relative fallbacks:
///   dart run spikes/spike3_schema_roundtrip/tool/generate.dart
library;

import 'dart:io';

// Relative import (not package:) so this script runs under any package
// config, including the repo-root workspace config which does not include
// this spike package.
import '../lib/src/generator.dart';

void main() {
  final packageRoot = _findPackageRoot();
  final catalogFile = File('$packageRoot/schema/catalog.json');
  final outputs = generateFromCatalog(catalogFile.readAsStringSync());

  final generatedDir = Directory('$packageRoot/lib/src/generated')
    ..createSync(recursive: true);
  final registryFile = File('${generatedDir.path}/registry.g.dart')
    ..writeAsStringSync(outputs.registryDart);
  final schemaFile = File('${generatedDir.path}/tool_schema.g.json')
    ..writeAsStringSync(outputs.toolSchemaJson);

  stdout
    ..writeln('generated ${registryFile.path}')
    ..writeln('generated ${schemaFile.path}');
}

String _findPackageRoot() {
  final candidates = <String>[
    // Platform.script -> .../spike3_schema_roundtrip/tool/generate.dart
    File.fromUri(Platform.script).parent.parent.path,
    // cwd == package root
    Directory.current.path,
    // cwd == repo root
    '${Directory.current.path}/spikes/spike3_schema_roundtrip',
  ];
  for (final c in candidates) {
    if (File('$c/schema/catalog.json').existsSync()) return c;
  }
  throw StateError(
    'could not locate spike3_schema_roundtrip/schema/catalog.json '
    '(tried: $candidates)',
  );
}
