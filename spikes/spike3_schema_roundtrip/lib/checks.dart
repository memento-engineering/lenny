/// Spike 3 shared checks — framework-free on purpose.
///
/// NO package:test import here. Each check is a plain function that THROWS
/// StateError with a descriptive message on failure. This is what makes the
/// dual-harness proof possible: test/spike3_test.dart (package:test, bare VM)
/// and spike3_flutter_harness/test/spike3_flutter_test.dart (flutter_test)
/// both call these EXACT functions — same checks, two bindings.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:perception/perception.dart';

import 'src/field.dart';
import 'src/generator.dart';
import 'src/wire.dart';

// ---------------------------------------------------------------------------
// Plumbing
// ---------------------------------------------------------------------------

void _require(bool condition, String message) {
  if (!condition) throw StateError('CHECK FAILED: $message');
}

void _expectStateError(String label, void Function() body) {
  try {
    body();
  } on StateError catch (e) {
    // Expected. Require a non-empty diagnostic so failures stay debuggable.
    _require(
      e.message.toString().isNotEmpty,
      '$label: threw StateError but with an empty message',
    );
    return;
  }
  throw StateError('CHECK FAILED: $label: expected a StateError, got none');
}

/// Package root of spike3_schema_roundtrip, located WITHOUT hardcoded paths
/// so the same code works under `dart test` (cwd = this package) and
/// `flutter test` (cwd = the sibling harness package).
///
/// Primary: Isolate.resolvePackageUriSync (bare VM). Fallback: walk up from
/// cwd to the nearest .dart_tool/package_config.json and resolve this
/// package's rootUri — needed because the flutter_test environment throws
/// UnsupportedError from resolvePackageUriSync.
String packageRoot() {
  Uri? libUri;
  try {
    libUri = Isolate.resolvePackageUriSync(
      Uri.parse('package:spike3_schema_roundtrip/checks.dart'),
    );
  } on UnsupportedError {
    libUri = null;
  }
  if (libUri != null) return File.fromUri(libUri).parent.parent.path;

  var dir = Directory.current.absolute;
  while (true) {
    final configFile = File('${dir.path}/.dart_tool/package_config.json');
    if (configFile.existsSync()) {
      final config = (jsonDecode(configFile.readAsStringSync()) as Map)
          .cast<String, Object?>();
      for (final p in (config['packages'] as List).cast<Map>()) {
        if (p['name'] == 'spike3_schema_roundtrip') {
          // rootUri is a directory reference relative to the config file
          // (e.g. "../../spike3_schema_roundtrip" or "../").
          final raw = p['rootUri'] as String;
          final rootUri = configFile.uri.resolve(
            raw.endsWith('/') ? raw : '$raw/',
          );
          final path = rootUri.toFilePath();
          return path.endsWith(Platform.pathSeparator)
              ? path.substring(0, path.length - 1)
              : path;
        }
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError(
    'could not locate the spike3_schema_roundtrip package root from '
    '${Directory.current.path}',
  );
}

String _readPackageFile(String relativePath) {
  final file = File('${packageRoot()}/$relativePath');
  if (!file.existsSync()) {
    throw StateError(
      'CHECK FAILED: expected file is missing: ${file.path} '
      '(did you run tool/generate.dart?)',
    );
  }
  return file.readAsStringSync();
}

// ---------------------------------------------------------------------------
// Fixture messages (A2UI v0.9 updateComponents shape)
// ---------------------------------------------------------------------------

/// v1: root node + 4 keyed children (mix of node/field); the node child has
/// a nested field so the reconcile check can also assert deep identity.
Map<String, Object?> messageV1() => {
  'version': 'v0.9',
  'updateComponents': {
    'surfaceId': 'spike3-surface',
    'components': [
      {
        'id': 'root',
        'component': 'node',
        'name': 'profile-form',
        'children': ['f_name', 'f_email', 'n_addr', 'f_age'],
      },
      {'id': 'f_name', 'component': 'field', 'name': 'Name', 'value': 'Nico'},
      {
        'id': 'f_email',
        'component': 'field',
        'name': 'Email',
        'value': 'nico@example.com',
      },
      {
        'id': 'n_addr',
        'component': 'node',
        'name': 'address',
        'children': ['f_street'],
      },
      {
        'id': 'f_street',
        'component': 'field',
        'name': 'Street',
        'value': '1 Main St',
      },
      {'id': 'f_age', 'component': 'field', 'name': 'Age', 'value': '38'},
    ],
  },
};

/// v2: a WHOLE-tree re-emission of v1 with, relative to v1's child list:
///   - prop changed:  f_name value "Nico" -> "Nico Spencer"
///   - removed:       f_age
///   - inserted:      f_phone (new)
///   - reordered:     f_email and n_addr swap positions
Map<String, Object?> messageV2() => {
  'version': 'v0.9',
  'updateComponents': {
    'surfaceId': 'spike3-surface',
    'components': [
      {
        'id': 'root',
        'component': 'node',
        'name': 'profile-form',
        'children': ['f_name', 'n_addr', 'f_email', 'f_phone'],
      },
      {
        'id': 'f_name',
        'component': 'field',
        'name': 'Name',
        'value': 'Nico Spencer',
      },
      {
        'id': 'n_addr',
        'component': 'node',
        'name': 'address',
        'children': ['f_street'],
      },
      {
        'id': 'f_street',
        'component': 'field',
        'name': 'Street',
        'value': '1 Main St',
      },
      {
        'id': 'f_email',
        'component': 'field',
        'name': 'Email',
        'value': 'nico@example.com',
      },
      {
        'id': 'f_phone',
        'component': 'field',
        'name': 'Phone',
        'value': '555-0100',
      },
    ],
  },
};

// ---------------------------------------------------------------------------
// (a) generator-in-sync: ONE source, TWO projections, deterministic
// ---------------------------------------------------------------------------

void checkGeneratorInSync() {
  final catalog = _readPackageFile('schema/catalog.json');
  final fresh = generateFromCatalog(catalog);
  // Determinism: generating twice from the same source is byte-identical.
  final again = generateFromCatalog(catalog);
  _require(
    fresh.registryDart == again.registryDart &&
        fresh.toolSchemaJson == again.toolSchemaJson,
    'generator is not deterministic: two in-memory runs differ',
  );

  final registryOnDisk = _readPackageFile('lib/src/generated/registry.g.dart');
  final schemaOnDisk = _readPackageFile(
    'lib/src/generated/tool_schema.g.json',
  );
  _require(
    registryOnDisk == fresh.registryDart,
    'lib/src/generated/registry.g.dart is OUT OF SYNC with '
    'schema/catalog.json — re-run tool/generate.dart '
    '(disk: ${registryOnDisk.length} chars, fresh: '
    '${fresh.registryDart.length} chars, first diff at index '
    '${_firstDiff(registryOnDisk, fresh.registryDart)})',
  );
  _require(
    schemaOnDisk == fresh.toolSchemaJson,
    'lib/src/generated/tool_schema.g.json is OUT OF SYNC with '
    'schema/catalog.json — re-run tool/generate.dart '
    '(first diff at index ${_firstDiff(schemaOnDisk, fresh.toolSchemaJson)})',
  );
  // Provenance markers.
  _require(
    registryOnDisk.startsWith('// GENERATED — do not edit.'),
    'registry.g.dart is missing the GENERATED header',
  );
  _require(
    schemaOnDisk.contains('GENERATED — do not edit.'),
    'tool_schema.g.json is missing the GENERATED marker',
  );
}

int _firstDiff(String a, String b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    if (a.codeUnitAt(i) != b.codeUnitAt(i)) return i;
  }
  return n;
}

// ---------------------------------------------------------------------------
// (b) registry round-trip: flat wire message -> typed Perception tree
// ---------------------------------------------------------------------------

void checkRegistryRoundTrip() {
  final root = perceptionFromMessage(messageV1());

  _require(root is Node, 'root should be a Node, got ${root.runtimeType}');
  final rootNode = root as Node;
  _require(root.key == 'root', 'root key should be "root", got ${root.key}');
  _require(
    rootNode.name == 'profile-form',
    'root name prop should be "profile-form", got "${rootNode.name}"',
  );
  _require(
    rootNode.children.length == 4,
    'root should have 4 children, got ${rootNode.children.length}',
  );

  final keys = [for (final c in rootNode.children) c.key];
  _require(
    keys.join(',') == 'f_name,f_email,n_addr,f_age',
    'child keys should preserve wire childIds order, got $keys',
  );

  final fName = rootNode.children[0];
  _require(
    fName is Field && fName.name == 'Name' && fName.value == 'Nico',
    'f_name should be Field(name: Name, value: Nico), got $fName',
  );
  final fEmail = rootNode.children[1];
  _require(
    fEmail is Field &&
        fEmail.name == 'Email' &&
        fEmail.value == 'nico@example.com',
    'f_email props did not round-trip',
  );
  final nAddr = rootNode.children[2];
  _require(
    nAddr is Node && nAddr.name == 'address' && nAddr.children.length == 1,
    'n_addr should be Node(address) with 1 child',
  );
  final fStreet = (nAddr as Node).children.single;
  _require(
    fStreet is Field &&
        fStreet.key == 'f_street' &&
        fStreet.name == 'Street' &&
        fStreet.value == '1 Main St',
    'nested f_street did not round-trip',
  );
  final fAge = rootNode.children[3];
  _require(
    fAge is Field && fAge.name == 'Age' && fAge.value == '38',
    'f_age props did not round-trip',
  );
}

// ---------------------------------------------------------------------------
// (c) tool-schema sanity: catalog descriptions flowed into the LLM schema
// ---------------------------------------------------------------------------

void checkToolSchemaSanity() {
  final catalog = (jsonDecode(_readPackageFile('schema/catalog.json')) as Map)
      .cast<String, Object?>();
  final catalogTypes = (catalog['types'] as Map).cast<String, Object?>();

  final schema =
      (jsonDecode(_readPackageFile('lib/src/generated/tool_schema.g.json'))
              as Map)
          .cast<String, Object?>();

  final updateComponents =
      ((schema['properties'] as Map)['updateComponents'] as Map)
          .cast<String, Object?>();
  final components = ((updateComponents['properties'] as Map)['components']
          as Map)
      .cast<String, Object?>();
  final oneOf = ((components['items'] as Map)['oneOf'] as List)
      .cast<Map<dynamic, dynamic>>();

  // Index the per-type schemas by their "component" const discriminator.
  final byType = <String, Map<String, Object?>>{};
  for (final variant in oneOf) {
    final v = variant.cast<String, Object?>();
    final componentProp = ((v['properties'] as Map)['component'] as Map)
        .cast<String, Object?>();
    byType[componentProp['const'] as String] = v;
  }

  _require(
    byType.keys.toSet().containsAll({'node', 'field'}) &&
        byType.length == catalogTypes.length,
    'tool schema should contain exactly the catalog types '
    '(${catalogTypes.keys.toList()..sort()}), got '
    '(${byType.keys.toList()..sort()})',
  );

  for (final entry in catalogTypes.entries) {
    final typeName = entry.key;
    final catalogType = (entry.value as Map).cast<String, Object?>();
    final variant = byType[typeName]!;
    _require(
      variant['description'] == catalogType['description'],
      'type "$typeName": description did not flow from catalog into '
      'tool schema',
    );
    final variantProps = (variant['properties'] as Map)
        .cast<String, Object?>();
    final required = (variant['required'] as List).cast<String>();
    _require(
      required.contains('id') && required.contains('component'),
      'type "$typeName": id and component must be required',
    );
    final catalogProps = (catalogType['props'] as Map).cast<String, Object?>();
    for (final propEntry in catalogProps.entries) {
      final propName = propEntry.key;
      final catalogProp = (propEntry.value as Map).cast<String, Object?>();
      final variantProp = (variantProps[propName] as Map?)
          ?.cast<String, Object?>();
      _require(
        variantProp != null,
        'type "$typeName": prop "$propName" missing from tool schema',
      );
      _require(
        variantProp!['description'] == catalogProp['description'],
        'type "$typeName" prop "$propName": description did not flow from '
        'catalog into tool schema',
      );
      _require(
        variantProp['type'] == catalogProp['type'],
        'type "$typeName" prop "$propName": type did not flow from catalog',
      );
      _require(
        required.contains(propName),
        'type "$typeName": required prop "$propName" not marked required '
        'in tool schema',
      );
    }
    final isContainer = catalogType['container'] as bool;
    if (isContainer) {
      _require(
        variantProps.containsKey('children'),
        'container type "$typeName" should allow "children" in tool schema',
      );
    } else {
      _require(
        !variantProps.containsKey('children'),
        'leaf type "$typeName" must NOT have "children" in tool schema',
      );
      _require(
        variant['additionalProperties'] == false,
        'leaf type "$typeName" must set additionalProperties:false so '
        '"children" is forbidden, not just undocumented',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// (d) KEYED RECONCILE IDENTITY — the A3 crux:
//     whole-subtree emission reconciles to an identity-preserving patch
// ---------------------------------------------------------------------------

void checkKeyedReconcileIdentity() {
  final owner = PerceptionOwner();
  try {
    final rootEl = owner.mountRoot(perceptionFromMessage(messageV1()));
    _require(rootEl is NodeElement, 'root element should be a NodeElement');
    final rootNodeEl = rootEl as NodeElement;

    // Capture the v1 child element INSTANCES, by wire component id (== key).
    final oldChildren = List<PerceptionElement>.of(rootNodeEl.children);
    final oldByKey = {
      for (final el in oldChildren) el.perception.key! as String: el,
    };
    _require(
      oldByKey.keys.join(',') == 'f_name,f_email,n_addr,f_age',
      'v1 mount produced unexpected children: ${oldByKey.keys.toList()}',
    );
    final oldStreetEl = (oldByKey['n_addr']! as NodeElement).children.single;
    _require(
      oldStreetEl.perception.key == 'f_street',
      'v1 nested child should be f_street',
    );
    final oldNamePerception = oldByKey['f_name']!.perception;

    // WHOLE-tree re-emission: deserialize v2 and hand the new root config to
    // the existing root element. canUpdate holds (same runtimeType Node,
    // same stable key "root"), so this is an in-place update.
    rootNodeEl.update(perceptionFromMessage(messageV2()));

    final newChildren = rootNodeEl.children;
    _require(
      newChildren.length == 4,
      'v2 should have 4 children, got ${newChildren.length}',
    );
    final newKeys = [for (final el in newChildren) el.perception.key];
    _require(
      newKeys.join(',') == 'f_name,n_addr,f_email,f_phone',
      'v2 child order wrong: $newKeys',
    );

    // PROP-CHANGED: same element instance, new perception config.
    _require(
      identical(newChildren[0], oldByKey['f_name']),
      'f_name (prop changed) must be the SAME element instance',
    );
    _require(
      !identical(newChildren[0].perception, oldNamePerception),
      'f_name element should carry the NEW perception config object',
    );
    _require(
      (newChildren[0].perception as Field).value == 'Nico Spencer',
      'f_name element should see the updated value prop, got '
      '"${(newChildren[0].perception as Field).value}"',
    );

    // REORDERED: same instances at their NEW indices (v1: f_email@1,
    // n_addr@2 -> v2: n_addr@1, f_email@2).
    _require(
      identical(newChildren[1], oldByKey['n_addr']),
      'n_addr (reordered 2->1) must be the SAME element instance',
    );
    _require(
      identical(newChildren[2], oldByKey['f_email']),
      'f_email (reordered 1->2) must be the SAME element instance',
    );

    // DEEP identity: the field nested inside the moved n_addr subtree also
    // survives whole-tree re-emission.
    _require(
      identical(
        (newChildren[1] as NodeElement).children.single,
        oldStreetEl,
      ),
      'nested f_street inside the moved n_addr must be the SAME element '
      'instance',
    );

    // REMOVED: old instance unmounted.
    _require(
      !oldByKey['f_age']!.mounted,
      'f_age (removed in v2) must be unmounted',
    );

    // INSERTED: fresh instance, mounted.
    final phoneEl = newChildren[3];
    _require(
      oldChildren.every((old) => !identical(old, phoneEl)),
      'f_phone (inserted) must be a FRESH element instance',
    );
    _require(phoneEl.mounted, 'f_phone must be mounted');

    // KEPT instances stayed mounted throughout.
    for (final id in ['f_name', 'f_email', 'n_addr']) {
      _require(oldByKey[id]!.mounted, '$id must still be mounted after v2');
    }
  } finally {
    owner.dispose();
  }
}

// ---------------------------------------------------------------------------
// (e) rejection paths
// ---------------------------------------------------------------------------

Map<String, Object?> _envelope(List<Map<String, Object?>> components) => {
  'version': 'v0.9',
  'updateComponents': {'surfaceId': 's', 'components': components},
};

void checkRejections() {
  // Dangling childId.
  _expectStateError('dangling childId', () {
    perceptionFromMessage(
      _envelope([
        {
          'id': 'root',
          'component': 'node',
          'name': 'r',
          'children': ['ghost'],
        },
      ]),
    );
  });

  // Duplicate id.
  _expectStateError('duplicate id', () {
    perceptionFromMessage(
      _envelope([
        {'id': 'root', 'component': 'node', 'name': 'r'},
        {'id': 'dup', 'component': 'field', 'name': 'a', 'value': '1'},
        {'id': 'dup', 'component': 'field', 'name': 'b', 'value': '2'},
      ]),
    );
  });

  // Unknown component type (registry-level rejection).
  _expectStateError('unknown type', () {
    perceptionFromMessage(
      _envelope([
        {'id': 'root', 'component': 'button', 'label': 'no such type'},
      ]),
    );
  });

  // Mistyped prop (registry-level rejection).
  _expectStateError('bad prop type', () {
    perceptionFromMessage(
      _envelope([
        {'id': 'root', 'component': 'field', 'name': 42, 'value': 'x'},
      ]),
    );
  });

  // Missing required prop (registry-level rejection).
  _expectStateError('missing required prop', () {
    perceptionFromMessage(
      _envelope([
        {'id': 'root', 'component': 'field', 'name': 'only-name'},
      ]),
    );
  });

  // Children handed to a leaf (registry-level rejection).
  _expectStateError('children on leaf', () {
    perceptionFromMessage(
      _envelope([
        {
          'id': 'root',
          'component': 'field',
          'name': 'n',
          'value': 'v',
          'children': ['extra'],
        },
        {'id': 'extra', 'component': 'field', 'name': 'e', 'value': 'x'},
      ]),
    );
  });

  // Unknown rootId.
  _expectStateError('unknown rootId', () {
    perceptionFromMessage({
      'version': 'v0.9',
      'updateComponents': {
        'surfaceId': 's',
        'rootId': 'nope',
        'components': [
          {'id': 'root', 'component': 'node', 'name': 'r'},
        ],
      },
    });
  });

  // Cycle.
  _expectStateError('cycle', () {
    perceptionFromMessage(
      _envelope([
        {
          'id': 'root',
          'component': 'node',
          'name': 'r',
          'children': ['a'],
        },
        {
          'id': 'a',
          'component': 'node',
          'name': 'a',
          'children': ['root'],
        },
      ]),
    );
  });
}

/// All checks, in spec order — handy for harnesses that want one entry point.
const Map<String, void Function()> allChecks = {
  '(a) generator-in-sync: one source, two projections, deterministic':
      checkGeneratorInSync,
  '(b) registry round-trip: flat wire message -> typed Perception tree':
      checkRegistryRoundTrip,
  '(c) tool-schema sanity: catalog descriptions flow into LLM schema':
      checkToolSchemaSanity,
  '(d) keyed reconcile identity: whole-tree emission becomes a keyed patch':
      checkKeyedReconcileIdentity,
  '(e) rejection paths: dangling/duplicate/unknown/bad-prop/leaf-children':
      checkRejections,
};
