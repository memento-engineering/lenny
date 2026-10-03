import 'dart:io';

const Map<String, String> _packageVersions = <String, String>{
  'packages/leonard_contract/pubspec.yaml': '0.2.6',
  'packages/leonard_host/pubspec.yaml': '0.2.4',
  'packages/leonard_flutter/pubspec.yaml': '0.4.1',
  'packages/leonard_dio/pubspec.yaml': '0.4.1',
  'packages/leonard_riverpod/pubspec.yaml': '0.4.1',
  'packages/leonard_router/pubspec.yaml': '0.4.1',
  'packages/leonard_tmux/pubspec.yaml': '0.2.3',
  'packages/leonard_native/pubspec.yaml': '0.4.2',
  'packages/leonard_devtools/pubspec.yaml': '0.4.0-dev.2',
};

const List<String> _perceptionManifests = <String>[
  'packages/leonard_contract/pubspec.yaml',
  'packages/leonard_host/pubspec.yaml',
  'packages/leonard_flutter/pubspec.yaml',
  'packages/leonard_dio/pubspec.yaml',
  'packages/leonard_riverpod/pubspec.yaml',
  'packages/leonard_router/pubspec.yaml',
  'packages/leonard_tmux/pubspec.yaml',
  'packages/leonard_native/pubspec.yaml',
];

const Map<String, Map<String, String>> _siblingFloors =
    <String, Map<String, String>>{
      'packages/leonard_host/pubspec.yaml': <String, String>{
        'leonard_contract': '^0.2.6',
      },
      'packages/leonard_flutter/pubspec.yaml': <String, String>{
        'leonard_contract': '^0.2.6',
      },
      'packages/leonard_dio/pubspec.yaml': <String, String>{
        'leonard_flutter': '^0.4.1',
      },
      'packages/leonard_riverpod/pubspec.yaml': <String, String>{
        'leonard_flutter': '^0.4.1',
      },
      'packages/leonard_router/pubspec.yaml': <String, String>{
        'leonard_flutter': '^0.4.1',
      },
      'packages/leonard_tmux/pubspec.yaml': <String, String>{
        'leonard_contract': '^0.2.6',
        'leonard_host': '^0.2.4',
      },
      'packages/leonard_native/pubspec.yaml': <String, String>{
        'leonard_contract': '^0.2.6',
        'leonard_host': '^0.2.4',
      },
    };

const List<String> _sourceRoots = <String>[
  'packages/leonard_contract',
  'packages/leonard_host',
  'packages/leonard_flutter',
  'packages/leonard_dio',
  'packages/leonard_riverpod',
  'packages/leonard_router',
  'packages/leonard_tmux',
  'packages/leonard_native',
  'packages/leonard_devtools',
];

void main() {
  final List<String> failures = <String>[];

  for (final MapEntry<String, String> entry in _packageVersions.entries) {
    final String contents = File(entry.key).readAsStringSync();
    _expectYamlValue(contents, entry.key, 'version', entry.value, failures);
    if (RegExp(r'^\s+path:\s*', multiLine: true).hasMatch(contents)) {
      failures.add('${entry.key}: path dependency is not allowed');
    }
  }

  for (final String path in _perceptionManifests) {
    _expectYamlValue(
      File(path).readAsStringSync(),
      path,
      'genesis_perception',
      '^0.4.0-dev.1',
      failures,
    );
  }

  for (final MapEntry<String, Map<String, String>> manifest
      in _siblingFloors.entries) {
    final String contents = File(manifest.key).readAsStringSync();
    for (final MapEntry<String, String> dependency
        in manifest.value.entries) {
      _expectYamlValue(
        contents,
        manifest.key,
        dependency.key,
        dependency.value,
        failures,
      );
    }
  }

  const String devtoolsManifest = 'packages/leonard_devtools/pubspec.yaml';
  _expectYamlValue(
    File(devtoolsManifest).readAsStringSync(),
    devtoolsManifest,
    'genesis_foundation',
    '^0.3.0-dev.1',
    failures,
  );

  const String fixtureManifest =
      'packages/leonard_flutter/example/diagnostic_fixture/pubspec.yaml';
  final String fixture = File(fixtureManifest).readAsStringSync();
  _expectYamlValue(
    fixture,
    fixtureManifest,
    'genesis_perception',
    '^0.4.0-dev.1',
    failures,
  );
  if (RegExp(r'^\s+path:\s*', multiLine: true).hasMatch(fixture)) {
    failures.add('$fixtureManifest: path dependency is not allowed');
  }

  _auditMigrationGuide(failures);
  _auditDartVocabulary(failures);

  if (failures.isNotEmpty) {
    throw StateError(
      'component vocabulary audit failed:\n${failures.join('\n')}',
    );
  }

  stdout.writeln(
    'Component vocabulary audit passed: 8 Genesis floors, 9 package '
    'versions, docs, compatibility, and first-party Dart sources.',
  );
}

void _expectYamlValue(
  String contents,
  String path,
  String key,
  String expected,
  List<String> failures,
) {
  final RegExp pattern = RegExp(
    '^\\s*$key:\\s*${RegExp.escape(expected)}\\s*\$',
    multiLine: true,
  );
  if (!pattern.hasMatch(contents)) {
    failures.add('$path: expected $key: $expected');
  }
}

void _auditMigrationGuide(List<String> failures) {
  const String path = 'docs/migrations/genesis-component-api.md';
  final String guide = File(path).readAsStringSync();
  const List<String> required = <String>[
    '`Seed` | `Component`',
    '`Branch` | `Element`',
    '`TreeContext` | Genesis `BuildContext`',
    '`seed` | `component`',
    '`branchId` | `elementId`',
    'inherited-seed lookup names | inherited-value lookup names',
    '`buildCorePerceptionSeed` | `buildCorePerceptionComponent`',
    '`TreeNode.seedType` | `TreeNode.componentType`',
    'identity-preserving aliases',
    'literal `seedType`\nJSON key',
    '`grid_assets/leonard_grid_assets`',
    'as genesis',
  ];
  for (final String statement in required) {
    if (!guide.contains(statement)) {
      failures.add('$path: missing required statement "$statement"');
    }
  }
}

void _auditDartVocabulary(List<String> failures) {
  final RegExp legacyTypes = RegExp(r'\b(?:Seed|Branch|TreeContext|TreeOwner)\b');
  final List<RegExp> legacyMembers = <RegExp>[
    RegExp(r'\bbuildCorePerceptionSeed\b'),
    RegExp(r'\.seedType\b'),
    RegExp(r'\bseedType\s*:'),
    RegExp(r'\.branchId\b'),
    RegExp(r'\bbranchId\s*:'),
    RegExp(r'\.seed\b'),
    RegExp(r'\bseed\s*:'),
  ];

  for (final String root in _sourceRoots) {
    for (final FileSystemEntity entity in Directory(root).listSync(
      recursive: true,
    )) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.contains('/.dart_tool/')) continue;
      if (entity.path.endsWith(
        'perception_extension_compatibility_test.dart',
      )) {
        continue;
      }
      final List<String> lines = entity.readAsLinesSync();
      for (var index = 0; index < lines.length; index += 1) {
        final String line = lines[index];
        final bool allowedNaturalBranch = line.contains('Branch on this code');
        if (legacyTypes.hasMatch(line) && !allowedNaturalBranch) {
          failures.add('${entity.path}:${index + 1}: legacy Genesis type');
        }
        for (final RegExp pattern in legacyMembers) {
          if (pattern.hasMatch(line)) {
            failures.add(
              '${entity.path}:${index + 1}: legacy Genesis member',
            );
          }
        }
      }
    }
  }
}
