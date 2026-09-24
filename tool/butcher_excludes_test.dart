import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory package;
  late File configuration;

  setUp(() {
    package = Directory(
      Directory.systemTemp
          .createTempSync('butcher-excludes-')
          .resolveSymbolicLinksSync(),
    );
    File(
      '${package.path}/pubspec.yaml',
    ).writeAsStringSync('name: portable_package\n');
    Directory('${package.path}/lib/src').createSync(recursive: true);
    for (final String source in <String>[
      'lib/a.dart',
      'lib/b.dart',
      'lib/src/c.dart',
    ]) {
      File('${package.path}/$source').writeAsStringSync('const int x = 1;\n');
    }
    File('${package.path}/lib/not_dart.txt').writeAsStringSync('ignored\n');
    configuration = File('${package.path}/butcher.yaml');
  });

  tearDown(() => package.deleteSync(recursive: true));

  ProcessResult generate(List<String> arguments) =>
      Process.runSync('dart', <String>[
        'run',
        '${_workspaceRoot().path}/tool/butcher_excludes.dart',
        ...arguments,
      ]);

  test('an empty selection writes no file, leaving the library in scope', () {
    final ProcessResult result = generate(<String>[package.path]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(configuration.existsSync(), isFalse);
    expect(result.stdout, contains('the whole library is in scope'));
  });

  test('a one-source selection excludes every other source', () {
    final ProcessResult result = generate(<String>[package.path, 'lib/b.dart']);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(
      configuration.readAsLinesSync().where(
        (String line) => line.startsWith('  - '),
      ),
      <String>["  - 'lib/a.dart'", "  - 'lib/src/c.dart'"],
    );
    expect(configuration.readAsStringSync(), contains('exclude:'));
    expect(configuration.readAsStringSync(), isNot(contains('lib/b.dart')));
    expect(configuration.readAsStringSync(), isNot(contains('not_dart.txt')));
  });

  test('a full selection excludes nothing', () {
    final ProcessResult result = generate(<String>[
      package.path,
      'lib/a.dart',
      'lib/b.dart',
      'lib/src/c.dart',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(configuration.readAsStringSync(), contains('exclude: []'));
    expect(
      configuration.readAsLinesSync().where(
        (String line) => line.startsWith('  - '),
      ),
      isEmpty,
    );
  });

  test('a selection naming a missing file is an error', () {
    final ProcessResult result = generate(<String>[
      package.path,
      'lib/a.dart',
      'lib/absent.dart',
    ]);

    expect(result.exitCode, 66);
    expect(result.stderr, contains('lib/absent.dart'));
    expect(configuration.existsSync(), isFalse);
  });

  test('a selection naming a test source is an error', () {
    Directory('${package.path}/test').createSync();
    File(
      '${package.path}/test/a_test.dart',
    ).writeAsStringSync('void main() {}\n');

    final ProcessResult result = generate(<String>[
      package.path,
      'test/a_test.dart',
    ]);

    expect(result.exitCode, 66);
    expect(configuration.existsSync(), isFalse);
  });

  test('a hand-authored configuration is never clobbered', () {
    configuration.writeAsStringSync('exclude:\n  - lib/mine.dart\n');

    final ProcessResult result = generate(<String>[package.path, 'lib/a.dart']);

    expect(result.exitCode, 70);
    expect(result.stderr, contains('hand-authored'));
    expect(configuration.readAsStringSync(), contains('lib/mine.dart'));
  });

  test('a generated configuration is replaced and then removed', () {
    expect(generate(<String>[package.path, 'lib/a.dart']).exitCode, 0);
    expect(configuration.readAsStringSync(), contains("- 'lib/b.dart'"));

    expect(generate(<String>[package.path, 'lib/b.dart']).exitCode, 0);
    expect(configuration.readAsStringSync(), contains("- 'lib/a.dart'"));

    expect(generate(<String>[package.path]).exitCode, 0);
    expect(configuration.existsSync(), isFalse);
  });

  test('bad arity and an absent package are usage and input errors', () {
    expect(generate(<String>[]).exitCode, 64);
    expect(generate(<String>['${package.path}/absent']).exitCode, 66);
    File('${package.path}/pubspec.yaml').deleteSync();
    expect(generate(<String>[package.path]).exitCode, 66);
  });
}

Directory _workspaceRoot() {
  Directory current = Directory.current.absolute;
  while (!File('${current.path}/tool/butcher_excludes.dart').existsSync()) {
    if (current.parent.path == current.path) {
      throw StateError('workspace not found');
    }
    current = current.parent;
  }
  return current;
}
