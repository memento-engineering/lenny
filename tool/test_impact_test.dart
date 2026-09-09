import 'dart:io';

import 'package:test/test.dart';

void main() {
  final Directory workspace = _workspaceRoot();
  final String script = '${workspace.path}/tool/test_impact.dart';
  final Directory fixture = Directory(
    '${workspace.path}/tool/test_fixtures/test_impact',
  );
  late Directory temporaryDirectory;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync('test-impact-');
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  Future<ProcessResult> run(List<String> arguments) => Process.run(
    Platform.resolvedExecutable,
    <String>['run', script, ...arguments],
    workingDirectory: workspace.path,
  );

  test(
    'maps a transitive diamond once and falls back deterministically',
    () async {
      final Directory output = Directory(
        '${temporaryDirectory.path}/documents',
      );
      final ProcessResult result = await run(<String>[
        fixture.path,
        output.path,
        'lib/unrelated.dart',
        'lib/orphan.dart',
        'lib/base.dart',
        'lib/barrel.dart',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stderr, isEmpty);
      final List<String> manifest = (result.stdout as String).trim().split(
        '\n',
      );
      expect(manifest, hasLength(4));
      expect(manifest, orderedEquals(manifest.toList()..sort()));
      expect(
        manifest.map((String path) => File(path).uri.pathSegments.last),
        <String>[
          '000-lib-barrel.dart.xml',
          '001-lib-base.dart.xml',
          '002-lib-orphan.dart.xml',
          '003-lib-unrelated.dart.xml',
        ],
      );

      String document(String source) => manifest
          .map((String path) => File(path).readAsStringSync())
          .singleWhere((String xml) => xml.contains('<file>$source</file>'));

      final String base = document('lib/base.dart');
      expect(base, contains('dart test &apos;test/diamond_test.dart&apos;'));
      expect(RegExp('test/diamond_test.dart').allMatches(base), hasLength(1));
      expect(base, isNot(contains('unrelated_test.dart')));

      final String unrelated = document('lib/unrelated.dart');
      expect(
        unrelated,
        contains('dart test &apos;test/unrelated_test.dart&apos;'),
      );
      expect(unrelated, isNot(contains('diamond_test.dart')));

      for (final String source in <String>[
        'lib/orphan.dart',
        'lib/barrel.dart',
      ]) {
        expect(
          document(source),
          contains(
            '<command group="test" expected-return="0" '
            'working-directory=".">dart test</command>',
          ),
        );
      }
    },
  );

  test('returns 64 for usage, duplicate, and non-lib sources', () async {
    Future<void> expectUsage(List<String> arguments) async {
      final ProcessResult result = await run(arguments);
      expect(result.exitCode, 64, reason: result.stderr.toString());
      expect(result.stdout, isEmpty);
    }

    await expectUsage(<String>[]);
    await expectUsage(<String>[fixture.path, temporaryDirectory.path]);
    await expectUsage(<String>[
      fixture.path,
      '${temporaryDirectory.path}/out',
      'lib/base.dart',
      'lib/base.dart',
    ]);
    await expectUsage(<String>[
      fixture.path,
      '${temporaryDirectory.path}/out',
      'test/diamond_test.dart',
    ]);
    await expectUsage(<String>[
      fixture.path,
      '${temporaryDirectory.path}/out',
      'lib/../lib/base.dart',
    ]);
  });

  test('returns 66 for missing package inputs and output parent', () async {
    Future<void> expectMissing(List<String> arguments) async {
      final ProcessResult result = await run(arguments);
      expect(result.exitCode, 66, reason: result.stderr.toString());
      expect(result.stdout, isEmpty);
    }

    await expectMissing(<String>[
      '${temporaryDirectory.path}/missing-package',
      '${temporaryDirectory.path}/out',
      'lib/base.dart',
    ]);
    final Directory noPubspec = Directory('${temporaryDirectory.path}/package')
      ..createSync();
    await expectMissing(<String>[
      noPubspec.path,
      '${temporaryDirectory.path}/out',
      'lib/base.dart',
    ]);
    await expectMissing(<String>[
      fixture.path,
      '${temporaryDirectory.path}/out',
      'lib/missing.dart',
    ]);
    await expectMissing(<String>[
      fixture.path,
      '${temporaryDirectory.path}/missing/out',
      'lib/base.dart',
    ]);
  });
}

Directory _workspaceRoot() {
  Directory current = Directory.current.absolute;
  while (!File('${current.path}/tool/test_impact.dart').existsSync()) {
    if (current.parent.path == current.path) {
      throw StateError('workspace root not found');
    }
    current = current.parent;
  }
  return current;
}
