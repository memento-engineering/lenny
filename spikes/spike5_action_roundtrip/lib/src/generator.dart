/// Spike 5 codegen core — a thin WRAPPER around spike3's generator
/// (genesis A2 reuse probe: one generator core driving a second catalog).
///
/// Delegates the two existing projections (Dart factory registry + LLM tool
/// schema) to spike3's `generateFromCatalog`, then:
///   1. rebrands the generated-file provenance headers (spike3's headers are
///      hardcoded constants — parameterization gap, see NOTES.md);
///   2. AUGMENTS the tool schema with per-type action affordances read from
///      the catalog's `actions` extension (spike3's generator ignores unknown
///      type-level keys, so affordances would otherwise be silently dropped
///      from the LLM-facing projection — the central A5 requirement);
///   3. emits a third projection, actions.g.dart: catalog-derived action
///      affordance data (wire type -> declared actions) plus the
///      Perception-class -> wire-type mapping the action router's hit-test
///      uses. Nothing outside the generated files hardcodes which component
///      types afford which actions.
///
/// Like spike3's core, this library is pure (String in, Strings out) so the
/// SAME code path is exercised by tool/generate.dart (writes files) and by
/// the generator-in-sync test (compares in-memory output to disk).
library;

import 'dart:convert';

import 'package:spike3_schema_roundtrip/src/generator.dart' as spike3;

class GeneratedOutputs5 {
  const GeneratedOutputs5({
    required this.registryDart,
    required this.toolSchemaJson,
    required this.actionsDart,
  });

  /// Contents of lib/src/generated/registry.g.dart.
  final String registryDart;

  /// Contents of lib/src/generated/tool_schema.g.json.
  final String toolSchemaJson;

  /// Contents of lib/src/generated/actions.g.dart.
  final String actionsDart;
}

/// Generates all three projections from the raw catalog JSON string.
GeneratedOutputs5 generateSpike5(String catalogJsonString) {
  // REUSE: spike3's generator core produces the registry and the base tool
  // schema for this catalog unchanged.
  final base = spike3.generateFromCatalog(catalogJsonString);

  final catalog = (jsonDecode(catalogJsonString) as Map).cast<String, Object?>();
  final typesJson = (catalog['types'] as Map).cast<String, Object?>();
  // Stable ordering, matching spike3: types sorted by name.
  final typeNames = typesJson.keys.toList()..sort();

  final actionsByType = <String, Map<String, String>>{};
  final dartClassByType = <String, String>{};
  final dartImportByType = <String, String>{};
  for (final name in typeNames) {
    final t = (typesJson[name] as Map).cast<String, Object?>();
    final dart = (t['dart'] as Map).cast<String, Object?>();
    dartClassByType[name] = dart['class'] as String;
    dartImportByType[name] = dart['import'] as String;
    final actions = <String, String>{};
    final actionsRaw = t['actions'];
    if (actionsRaw != null) {
      final m = (actionsRaw as Map).cast<String, Object?>();
      final actionNames = m.keys.toList()..sort();
      for (final a in actionNames) {
        final spec = (m[a] as Map).cast<String, Object?>();
        actions[a] = spec['description'] as String;
      }
    }
    actionsByType[name] = actions;
  }

  return GeneratedOutputs5(
    registryDart: _rebrandProvenance(base.registryDart),
    toolSchemaJson: _augmentToolSchema(base.toolSchemaJson, actionsByType),
    actionsDart: _generateActions(
      typeNames,
      actionsByType,
      dartClassByType,
      dartImportByType,
    ),
  );
}

/// spike3's generated headers are hardcoded constants naming spike3 as the
/// generator; fix the provenance comment so the committed artifact is honest.
/// (Generator-parameterization gap — recorded in NOTES.md for A2/A6.)
String _rebrandProvenance(String s) => s.replaceAll(
  'tool/generate.dart (spike3)',
  'tool/generate.dart (spike5; emitted by spike3 generateFromCatalog)',
);

// ---------------------------------------------------------------------------
// Projection 2 augmentation: action affordances into the LLM tool schema
// ---------------------------------------------------------------------------

String _augmentToolSchema(
  String baseToolSchemaJson,
  Map<String, Map<String, String>> actionsByType,
) {
  final schema = (jsonDecode(baseToolSchemaJson) as Map).cast<String, Object?>();
  schema['title'] = 'updateComponents (spike5 catalog)';
  schema[r'$comment'] = _rebrandProvenance(schema[r'$comment'] as String);
  // spike3's top-level description also hardcodes "the spike3 catalog".
  schema['description'] = (schema['description'] as String).replaceAll(
    'the spike3 catalog',
    'the spike5 catalog',
  );

  final updateComponents =
      ((schema['properties'] as Map)['updateComponents'] as Map);
  final components =
      ((updateComponents['properties'] as Map)['components'] as Map);
  final oneOf = ((components['items'] as Map)['oneOf'] as List);

  for (final variantRaw in oneOf) {
    final variant = variantRaw as Map;
    final typeName =
        ((variant['properties'] as Map)['component'] as Map)['const'] as String;
    final actions = actionsByType[typeName] ?? const {};
    if (actions.isEmpty) continue; // non-actionable types declare nothing
    // Structured affordance declaration (JSON Schema x- extension keyword).
    variant['x-actions'] = {
      for (final e in actions.entries) e.key: {'description': e.value},
    };
    // And prose, so an LLM reading only descriptions still discovers it.
    final affordances =
        actions.entries.map((e) => '"${e.key}" — ${e.value}').join(' ');
    variant['description'] =
        '${variant['description']} AFFORDS CLIENT ACTIONS: the client may '
        'send an A2UI action message with sourceComponentId set to this '
        "component's id and one of these action names: $affordances";
  }
  return '${const JsonEncoder.withIndent('  ').convert(schema)}\n';
}

// ---------------------------------------------------------------------------
// Projection 3: catalog-derived action affordance data (actions.g.dart)
// ---------------------------------------------------------------------------

String _escapeDart(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll("'", r"\'")
    .replaceAll(r'$', r'\$');

String _generateActions(
  List<String> typeNames,
  Map<String, Map<String, String>> actionsByType,
  Map<String, String> dartClassByType,
  Map<String, String> dartImportByType,
) {
  final buf = StringBuffer()
    ..writeln('// GENERATED — do not edit.')
    ..writeln(
      '// Generated from schema/catalog.json by tool/generate.dart (spike5).',
    )
    ..writeln('//')
    ..writeln(
      '// Catalog-derived ACTION AFFORDANCES: which wire component types',
    )
    ..writeln(
      '// declare which client actions, plus the Perception-class ->',
    )
    ..writeln(
      '// wire-type mapping the action router uses to hit-test live elements',
    )
    ..writeln(
      '// against the catalog. Nothing outside this file hardcodes which',
    )
    ..writeln('// types afford which actions.')
    ..writeln();

  // Imports: package: imports first, then relative, each sorted (spike3 style).
  // package:perception is always needed for the Perception parameter type.
  final imports = {
    'package:perception/perception.dart',
    ...dartImportByType.values,
  }.toList()..sort();
  final packageImports = imports.where((i) => i.startsWith('package:'));
  final relativeImports = imports.where((i) => !i.startsWith('package:'));
  for (final i in packageImports) {
    buf.writeln("import '$i';");
  }
  if (relativeImports.isNotEmpty) {
    buf.writeln();
    for (final i in relativeImports) {
      buf.writeln("import '$i';");
    }
  }

  buf
    ..writeln()
    ..writeln('/// Wire type -> declared action name -> action description.')
    ..writeln('const Map<String, Map<String, String>> componentActions = {');
  for (final t in typeNames) {
    final actions = actionsByType[t]!;
    if (actions.isEmpty) {
      buf.writeln("  '$t': {},");
    } else {
      buf.writeln("  '$t': {");
      for (final e in actions.entries) {
        buf.writeln("    '${e.key}': '${_escapeDart(e.value)}',");
      }
      buf.writeln('  },');
    }
  }
  buf
    ..writeln('};')
    ..writeln()
    ..writeln(
      '/// Live Perception instance -> wire type name, via the catalog dart',
    )
    ..writeln('/// bindings. Null when the perception is not a catalog type.')
    ..writeln('String? wireTypeOfPerception(Perception perception) {');
  for (final t in typeNames) {
    buf.writeln("  if (perception is ${dartClassByType[t]}) return '$t';");
  }
  buf
    ..writeln('  return null;')
    ..writeln('}');
  return buf.toString();
}
