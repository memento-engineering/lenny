/// UNIT: locks the mutation pilot shell contract without executing mutants.
///
/// Each test copies the shipped runner into a temporary miniature workspace
/// and shadows `dart`/`flutter` with recording fakes, so mode, baseline,
/// coverage, test-runner selection and the score-gating branch are all
/// observable without touching workspace artifacts.
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory sourceRoot;
  late Directory sandbox;
  late File runner;
  late File invocationLog;
  late Map<String, String> environment;

  /// Absolute path of the artifact directory the runner writes for [mode].
  String outputDir(String mode, {String package = 'leonard_native'}) =>
      '${sandbox.path}/artifacts/mutation/$package/$mode';

  /// The `--rules <path> -b` prefix every mutation_test invocation carries.
  String rulesPrefix(String mode, {String package = 'leonard_native'}) =>
      'run mutation_test --rules '
      '${outputDir(mode, package: package)}/mutation_rules.xml -b';

  void writePubspec(String package, {required bool flutter}) {
    final Directory dir = Directory('${sandbox.path}/packages/$package')
      ..createSync(recursive: true);
    File('${dir.path}/pubspec.yaml').writeAsStringSync(
      flutter
          ? 'name: $package\n'
                'dependencies:\n'
                '  flutter:\n'
                '    sdk: flutter\n'
          : 'name: $package\n'
                'dependencies:\n'
                '  meta: ^1.16.0\n',
    );
  }

  setUp(() {
    sourceRoot = _findWorkspaceRoot();
    sandbox = Directory.systemTemp.createTempSync('mutation-pilot-test-');
    Directory('${sandbox.path}/tool').createSync(recursive: true);
    writePubspec('leonard_native', flutter: false);

    runner = File('${sandbox.path}/tool/run_mutation_pilot.sh');
    runner.writeAsStringSync(
      File('${sourceRoot.path}/tool/run_mutation_pilot.sh').readAsStringSync(),
    );
    final ProcessResult chmod = Process.runSync('chmod', <String>[
      '+x',
      runner.path,
    ]);
    expect(chmod.exitCode, 0, reason: 'chmod stderr: ${chmod.stderr}');

    final Directory fakeBin = Directory('${sandbox.path}/fake-bin')
      ..createSync();

    // Records every invocation. `MUTATION_FAKE_EXIT` lets a test drive the
    // below-threshold exit that mutation_test really produces.
    final File fakeDart = File('${fakeBin.path}/dart');
    fakeDart.writeAsStringSync(r'''#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MUTATION_FAKE_LOG"
if [[ "${1:-}" == "test" ]]; then
  echo "baseline tests passed"
  if [[ "${MUTATION_FAIL_BASELINE:-0}" == "1" ]]; then
    exit 1
  fi
  exit 0
fi
if [[ "${1:-}" == "run" && "${2:-}" == "mutation_test" ]]; then
  echo "542 mutations found"
  exit "${MUTATION_FAKE_EXIT:-0}"
fi
exit 70
''');
    // A Flutter package's baseline must go through `flutter test`, so the
    // fake logs under a distinguishable prefix.
    final File fakeFlutter = File('${fakeBin.path}/flutter');
    fakeFlutter.writeAsStringSync(r'''#!/usr/bin/env bash
printf 'flutter %s\n' "$*" >> "$MUTATION_FAKE_LOG"
exit 0
''');
    for (final File fake in <File>[fakeDart, fakeFlutter]) {
      final ProcessResult fakeChmod = Process.runSync('chmod', <String>[
        '+x',
        fake.path,
      ]);
      expect(
        fakeChmod.exitCode,
        0,
        reason: 'fake chmod stderr: ${fakeChmod.stderr}',
      );
    }

    invocationLog = File('${sandbox.path}/dart-invocations.txt');
    environment = <String, String>{
      ...Platform.environment,
      'PATH': '${fakeBin.path}:${Platform.environment['PATH'] ?? ''}',
      'MUTATION_FAKE_LOG': invocationLog.path,
    };
  });

  tearDown(() {
    sandbox.deleteSync(recursive: true);
  });

  group('argument handling', () {
    test('invalid mode exits 64 with usage and creates no artifacts', () async {
      final ProcessResult result = await _run(runner, environment, <String>[
        'invalid',
      ]);

      expect(result.exitCode, 64);
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('usage:'));
      expect(result.stderr, contains('[dry|full|pr]'));
      expect(Directory('${sandbox.path}/artifacts').existsSync(), isFalse);
      expect(invocationLog.existsSync(), isFalse);
    });

    test('an unknown package exits 66 and names where it looked', () async {
      final ProcessResult result = await _run(runner, environment, <String>[
        'full',
        'leonard_nope',
      ]);

      expect(result.exitCode, 66);
      expect(result.stderr, contains('no such package: leonard_nope'));
      expect(result.stderr, contains('${sandbox.path}/packages/leonard_nope'));
      expect(Directory('${sandbox.path}/artifacts').existsSync(), isFalse);
      expect(invocationLog.existsSync(), isFalse);
    });

    test('pr mode without a file list exits 64', () async {
      final ProcessResult result = await _run(runner, environment, <String>[
        'pr',
        'leonard_native',
      ]);

      expect(result.exitCode, 64);
      expect(result.stderr, contains('pr mode needs at least one file'));
      expect(invocationLog.existsSync(), isFalse);
    });
  });

  group('modes', () {
    test('dry mode counts only and leaves full artifacts absent', () async {
      final ProcessResult result = await _run(runner, environment, <String>[
        'dry',
      ]);

      expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
      expect(invocationLog.readAsLinesSync(), <String>[
        '${rulesPrefix('dry')} --dry --format none',
      ]);
      expect(result.stdout, contains('542 mutations found'));
      expect(
        File('${outputDir('dry')}/console.txt').readAsStringSync(),
        contains('542 mutations found'),
      );
      expect(Directory(outputDir('full')).existsSync(), isFalse);
    });

    test(
      'default full mode runs baseline then mutation without coverage',
      () async {
        final ProcessResult result = await _run(
          runner,
          environment,
          const <String>[],
        );

        expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
        expect(invocationLog.readAsLinesSync(), <String>[
          'test',
          '${rulesPrefix('full')} --format all --output ${outputDir('full')}',
        ]);
        expect(result.stdout, contains('no lcov at'));
        expect(
          File('${outputDir('full')}/console.txt').readAsStringSync(),
          contains('542 mutations found'),
        );
      },
    );

    test(
      'full mode transforms and supplies existing package coverage',
      () async {
        final File coverage = File(
          '${sandbox.path}/artifacts/coverage/leonard_native.lcov',
        )..createSync(recursive: true);
        coverage.writeAsStringSync(
          'TN:\nSF:packages/leonard_native/lib/src/native.dart\nDA:1,1\n'
          'end_of_record\n',
        );

        final ProcessResult result = await _run(runner, environment, <String>[
          'full',
        ]);

        expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
        expect(invocationLog.readAsLinesSync(), <String>[
          'test',
          '${rulesPrefix('full')} --format all --output ${outputDir('full')} '
              '--coverage ${outputDir('full')}/leonard_native.lcov',
        ]);
        expect(
          File('${outputDir('full')}/leonard_native.lcov').readAsStringSync(),
          contains('SF:lib/lib/src/native.dart'),
        );
        expect(result.stdout, isNot(contains('no lcov at')));
      },
    );

    test(
      'pr mode sweeps only the listed files, into the pr directory',
      () async {
        final ProcessResult result = await _run(runner, environment, <String>[
          'pr',
          'leonard_native',
          'lib/src/a.dart',
          'lib/src/b.dart',
        ]);

        expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
        expect(invocationLog.readAsLinesSync(), <String>[
          'test',
          '${rulesPrefix('pr')} --format all --output ${outputDir('pr')} '
              'lib/src/a.dart lib/src/b.dart',
        ]);
        expect(Directory(outputDir('full')).existsSync(), isFalse);
      },
    );

    test('a red baseline prevents mutation execution', () async {
      final ProcessResult result = await _run(
        runner,
        <String, String>{...environment, 'MUTATION_FAIL_BASELINE': '1'},
        <String>['full'],
      );

      expect(result.exitCode, 1);
      expect(invocationLog.readAsLinesSync(), <String>['test']);
      expect(File('${outputDir('full')}/console.txt').existsSync(), isFalse);
    });
  });

  group('test-runner selection', () {
    test('a pure-Dart package is driven by dart test', () async {
      await _run(runner, environment, <String>['full']);

      expect(invocationLog.readAsLinesSync().first, 'test');
      expect(
        File('${outputDir('full')}/mutation_rules.xml').readAsStringSync(),
        contains('>dart test</command>'),
      );
    });

    test(
      'a Flutter package is driven by flutter test, not dart test',
      () async {
        writePubspec('leonard_flutter', flutter: true);

        final ProcessResult result = await _run(runner, environment, <String>[
          'full',
          'leonard_flutter',
        ]);

        expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
        final List<String> calls = invocationLog.readAsLinesSync();
        expect(
          calls.first,
          'flutter test',
          reason: 'the baseline must use the Flutter runner',
        );
        expect(
          calls,
          isNot(contains('test')),
          reason: 'bare `dart test` must not run for a Flutter package',
        );
        // The per-mutant command and the baseline come from one detection, so
        // they cannot disagree.
        expect(
          File(
            '${outputDir('full', package: 'leonard_flutter')}/'
            'mutation_rules.xml',
          ).readAsStringSync(),
          contains('>flutter test</command>'),
        );
      },
    );
  });

  group('score gating', () {
    test('a below-threshold score reports but does not fail', () async {
      final ProcessResult result = await _run(
        runner,
        <String, String>{...environment, 'MUTATION_FAKE_EXIT': '255'},
        <String>['full'],
      );

      expect(
        result.exitCode,
        0,
        reason: 'gating is off; the lane reports and uploads',
      );
      expect(result.stdout, contains('mutation_test exited 255'));
      expect(result.stdout, contains('Reporting only (gating off)'));
      // The report still lands, which is the point of not failing.
      expect(File('${outputDir('full')}/console.txt').existsSync(), isTrue);
    });

    test('MUTATION_GATE=1 restores the hard failure', () async {
      final ProcessResult result = await _run(
        runner,
        <String, String>{
          ...environment,
          'MUTATION_FAKE_EXIT': '255',
          'MUTATION_GATE': '1',
        },
        <String>['full'],
      );

      expect(result.exitCode, 255);
      expect(result.stdout, contains('MUTATION_GATE=1 — failing this run'));
      expect(result.stdout, isNot(contains('Reporting only')));
    });

    test('a passing score is unaffected by the gating branch', () async {
      final ProcessResult result = await _run(runner, environment, <String>[
        'full',
      ]);

      expect(result.exitCode, 0);
      expect(result.stdout, isNot(contains('mutation_test exited')));
      expect(result.stdout, isNot(contains('Reporting only')));
    });
  });
}

Future<ProcessResult> _run(
  File runner,
  Map<String, String> environment,
  List<String> arguments,
) => Process.run(
  runner.path,
  arguments,
  workingDirectory: runner.parent.parent.path,
  environment: environment,
);

Directory _findWorkspaceRoot() {
  Directory current = Directory.current.absolute;
  while (true) {
    if (File('${current.path}/tool/run_mutation_pilot.sh').existsSync()) {
      return current;
    }
    final Directory parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not find tool/run_mutation_pilot.sh');
    }
    current = parent;
  }
}
