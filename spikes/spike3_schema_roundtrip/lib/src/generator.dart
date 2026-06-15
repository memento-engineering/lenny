/// Spike 3 codegen core: ONE schema source (schema/catalog.json), TWO
/// projections — a typed Dart factory registry and an LLM-facing JSON Schema.
///
/// This library is pure (String in, Strings out) so the SAME code path is
/// exercised by tool/generate.dart (writes files) and by the
/// generator-in-sync check in checks.dart (compares in-memory output to the
/// files on disk, proving determinism and provenance).
///
/// Spike scope: only `"type": "string"` props and `"required": true` props
/// are supported; the generator throws on anything else so unsupported
/// catalogs fail loudly instead of generating silently-wrong code.
library;

import 'dart:convert';

const String generatedHeaderDart =
    '// GENERATED — do not edit.\n'
    '// Generated from schema/catalog.json by tool/generate.dart (spike3).\n';

const String generatedHeaderJson =
    'GENERATED — do not edit. Generated from schema/catalog.json by '
    'tool/generate.dart (spike3).';

class GeneratedOutputs {
  const GeneratedOutputs({
    required this.registryDart,
    required this.toolSchemaJson,
  });

  /// Contents of lib/src/generated/registry.g.dart.
  final String registryDart;

  /// Contents of lib/src/generated/tool_schema.g.json.
  final String toolSchemaJson;
}

/// Parsed view of one catalog type entry.
class _CatalogType {
  _CatalogType(this.name, Map<String, Object?> json)
    : description = json['description'] as String,
      container = json['container'] as bool,
      props = _parseProps(name, json['props']),
      dartClass = (json['dart'] as Map)['class'] as String,
      dartImport = (json['dart'] as Map)['import'] as String,
      positionalProps = ((json['dart'] as Map)['positionalProps'] as List)
          .cast<String>(),
      namedProps = ((json['dart'] as Map)['namedProps'] as List)
          .cast<String>(),
      childrenParam = (json['dart'] as Map)['childrenParam'] as String? {
    if (container && childrenParam == null) {
      throw StateError(
        'catalog type "$name": container types need dart.childrenParam',
      );
    }
    if (!container && childrenParam != null) {
      throw StateError(
        'catalog type "$name": leaf types must not have dart.childrenParam',
      );
    }
    final declared = {...positionalProps, ...namedProps};
    if (declared.length != props.length ||
        !props.keys.every(declared.contains)) {
      throw StateError(
        'catalog type "$name": dart positional/named props '
        '(${declared.toList()..sort()}) must cover exactly the declared '
        'props (${props.keys.toList()..sort()})',
      );
    }
  }

  final String name;
  final String description;
  final bool container;
  final Map<String, _CatalogProp> props; // insertion order = catalog order
  final String dartClass;
  final String dartImport;
  final List<String> positionalProps;
  final List<String> namedProps;
  final String? childrenParam;

  static Map<String, _CatalogProp> _parseProps(String type, Object? raw) {
    final map = (raw as Map).cast<String, Object?>();
    return {
      for (final e in map.entries)
        e.key: _CatalogProp(type, e.key, (e.value as Map).cast()),
    };
  }
}

class _CatalogProp {
  _CatalogProp(String typeName, this.name, Map<String, Object?> json)
    : type = json['type'] as String,
      required = json['required'] as bool,
      description = json['description'] as String {
    if (type != 'string') {
      throw StateError(
        'catalog type "$typeName" prop "$name": spike generator only '
        'supports "string" props, got "$type"',
      );
    }
    if (!required) {
      throw StateError(
        'catalog type "$typeName" prop "$name": spike generator only '
        'supports required props',
      );
    }
  }

  final String name;
  final String type;
  final bool required;
  final String description;
}

/// Generates both projections from the raw catalog JSON string.
GeneratedOutputs generateFromCatalog(String catalogJsonString) {
  final catalog = (jsonDecode(catalogJsonString) as Map)
      .cast<String, Object?>();
  final typesJson = (catalog['types'] as Map).cast<String, Object?>();
  // Stable ordering: types sorted by name — this is what makes the output
  // deterministic regardless of catalog key order.
  final typeNames = typesJson.keys.toList()..sort();
  final types = [
    for (final n in typeNames)
      _CatalogType(n, (typesJson[n] as Map).cast<String, Object?>()),
  ];
  return GeneratedOutputs(
    registryDart: _generateRegistry(types),
    toolSchemaJson: _generateToolSchema(types),
  );
}

// ---------------------------------------------------------------------------
// Projection 1: Dart factory registry
// ---------------------------------------------------------------------------

String _generateRegistry(List<_CatalogType> types) {
  final buf = StringBuffer()
    ..write(generatedHeaderDart)
    ..writeln('//')
    ..writeln(
      '// Typed factory registry: wire type name -> Perception factory.',
    )
    ..writeln(
      '// Validates props and children at construction; nothing outside this',
    )
    ..writeln('// file hardcodes component type names.')
    ..writeln();

  // Imports: package: imports first, then relative, each sorted.
  final imports = types.map((t) => t.dartImport).toSet().toList()..sort();
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

  buf.writeln('''

typedef ComponentFactory =
    Perception Function(
      Map<String, Object?> props,
      List<Perception> children,
      Object? key,
    );

String _stringProp(String type, Map<String, Object?> props, String name) {
  final value = props[name];
  if (value == null) {
    throw StateError(
      'component type "\$type": missing required prop "\$name"',
    );
  }
  if (value is! String) {
    throw StateError(
      'component type "\$type": prop "\$name" must be a string, '
      'got \${value.runtimeType} (\$value)',
    );
  }
  return value;
}

void _knownPropsOnly(
  String type,
  Map<String, Object?> props,
  Set<String> known,
) {
  for (final key in props.keys) {
    if (!known.contains(key)) {
      throw StateError('component type "\$type": unknown prop "\$key"');
    }
  }
}

void _noChildren(String type, List<Perception> children) {
  if (children.isNotEmpty) {
    throw StateError(
      'component type "\$type" is a leaf and cannot have children '
      '(got \${children.length})',
    );
  }
}
''');

  buf.writeln('final Map<String, ComponentFactory> componentRegistry = {');
  for (final t in types) {
    final knownProps = t.props.keys.map((p) => "'$p'").join(', ');
    buf.writeln("  '${t.name}': (props, children, key) {");
    if (!t.container) {
      buf.writeln("    _noChildren('${t.name}', children);");
    }
    buf.writeln("    _knownPropsOnly('${t.name}', props, const {$knownProps});");
    buf.writeln('    return ${t.dartClass}(');
    for (final p in t.positionalProps) {
      buf.writeln("      _stringProp('${t.name}', props, '$p'),");
    }
    for (final p in t.namedProps) {
      buf.writeln("      $p: _stringProp('${t.name}', props, '$p'),");
    }
    if (t.container) {
      buf.writeln('      ${t.childrenParam}: children,');
    }
    buf.writeln('      key: key,');
    buf.writeln('    );');
    buf.writeln('  },');
  }
  buf.writeln('};');

  final knownTypesList = types.map((t) => t.name).join(', ');
  buf.writeln('''

/// Single entry point used by the wire deserializer. Unknown [type] -> error.
Perception buildComponent(
  String type,
  Map<String, Object?> props,
  List<Perception> children,
  Object? key,
) {
  final factory = componentRegistry[type];
  if (factory == null) {
    throw StateError(
      'unknown component type "\$type"; known types: $knownTypesList',
    );
  }
  return factory(props, children, key);
}''');
  return buf.toString();
}

// ---------------------------------------------------------------------------
// Projection 2: LLM-facing JSON Schema (tool schema)
// ---------------------------------------------------------------------------

String _generateToolSchema(List<_CatalogType> types) {
  Map<String, Object?> componentSchema(_CatalogType t) {
    final properties = <String, Object?>{
      'id': {
        'type': 'string',
        'description':
            'Unique, stable component id. Becomes the reconciliation key: '
            're-emit the same id to update a component in place.',
      },
      'component': {
        'const': t.name,
        'description': 'Component type discriminator.',
      },
      for (final p in t.props.values)
        p.name: {'type': p.type, 'description': p.description},
      if (t.container)
        'children': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              'Ordered ids of child components. Every id must appear as a '
              'component in the same components list.',
        },
    };
    return {
      'type': 'object',
      'description': t.description,
      'properties': properties,
      'required': [
        'id',
        'component',
        for (final p in t.props.values)
          if (p.required) p.name,
      ],
      'additionalProperties': false,
    };
  }

  final schema = <String, Object?>{
    r'$comment': generatedHeaderJson,
    r'$schema': 'https://json-schema.org/draft/2020-12/schema',
    'title': 'updateComponents (spike3 catalog)',
    'description':
        'A2UI v0.9-shaped updateComponents message for the spike3 catalog. '
        'Always emit the WHOLE component tree; the client reconciles by '
        'component id. Exactly one component must have id "root".',
    'type': 'object',
    'properties': {
      'version': {'const': 'v0.9'},
      'updateComponents': {
        'type': 'object',
        'properties': {
          'surfaceId': {
            'type': 'string',
            'description': 'Identifier of the surface being updated.',
          },
          'components': {
            'type': 'array',
            'description':
                'Flat adjacency list of components. Containers reference '
                'children by id.',
            'items': {
              'oneOf': [for (final t in types) componentSchema(t)],
            },
          },
        },
        'required': ['surfaceId', 'components'],
        'additionalProperties': false,
      },
    },
    'required': ['version', 'updateComponents'],
    'additionalProperties': false,
  };
  return '${const JsonEncoder.withIndent('  ').convert(schema)}\n';
}
