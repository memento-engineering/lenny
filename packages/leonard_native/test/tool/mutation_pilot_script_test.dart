/// UNIT: locks the mutation pilot shell contract without executing mutants.
///
/// Each test copies the shipped runner into a temporary miniature workspace
/// and shadows `dart` with a recording fake, so mode, baseline, and coverage
/// branches are observable without touching workspace artifacts.
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory sourceRoot;
  late Directory sandbox;
  late File runner;
  late File invocationLog;
  late Map<String, String> environment;

  setUp(() {
    sourceRoot = _findWorkspaceRoot();
    sandbox = Directory.systemTemp.createTempSync('mutation-pilot-test-');
    Directory('${sandbox.path}/tool').createSync(recursive: true);
    Directory(
      '${sandbox.path}/packages/leonard_native',
    ).createSync(recursive: true);

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
  exit 0
fi
exit 70
''');
    final ProcessResult fakeChmod = Process.runSync('chmod', <String>[
      '+x',
      fakeDart.path,
    ]);
    expect(
      fakeChmod.exitCode,
      0,
      reason: 'fake chmod stderr: ${fakeChmod.stderr}',
    );

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

  test('invalid mode exits 64 with usage and creates no artifacts', () async {
    final ProcessResult result = await _run(runner, environment, <String>[
      'invalid',
    ]);

    expect(result.exitCode, 64);
    expect(result.stdout, isEmpty);
    expect(result.stderr, contains('usage:'));
    expect(result.stderr, contains('[dry|full]'));
    expect(Directory('${sandbox.path}/artifacts').existsSync(), isFalse);
    expect(invocationLog.existsSync(), isFalse);
  });

  test('dry mode counts only and leaves full artifacts absent', () async {
    final ProcessResult result = await _run(runner, environment, <String>[
      'dry',
    ]);

    expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
    expect(invocationLog.readAsLinesSync(), <String>[
      'run mutation_test --dry --format none',
    ]);
    expect(result.stdout, contains('542 mutations found'));
    expect(
      File(
        '${sandbox.path}/artifacts/mutation/leonard_native/dry/console.txt',
      ).readAsStringSync(),
      contains('542 mutations found'),
    );
    expect(
      Directory(
        '${sandbox.path}/artifacts/mutation/leonard_native/full',
      ).existsSync(),
      isFalse,
    );
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
      final List<String> calls = invocationLog.readAsLinesSync();
      expect(calls, hasLength(2));
      expect(calls.first, 'test');
      expect(
        calls.last,
        startsWith('run mutation_test --format all --output '),
      );
      expect(calls.last, isNot(contains('--coverage')));
      expect(
        File(
          '${sandbox.path}/artifacts/mutation/leonard_native/full/console.txt',
        ).readAsStringSync(),
        contains('542 mutations found'),
      );
    },
  );

  test('full mode transforms and supplies existing package coverage', () async {
    final File coverage = File(
      '${sandbox.path}/artifacts/coverage/leonard_native.lcov',
    )..createSync(recursive: true);
    coverage.writeAsStringSync(
      'TN:\nSF:packages/leonard_native/lib/src/native.dart\nDA:1,1\nend_of_record\n',
    );

    final ProcessResult result = await _run(runner, environment, <String>[
      'full',
    ]);

    expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
    final List<String> calls = invocationLog.readAsLinesSync();
    expect(calls.first, 'test');
    expect(calls.last, contains('--coverage '));
    expect(
      calls.last,
      contains(
        '${sandbox.path}/artifacts/mutation/leonard_native/full/'
        'leonard_native.lcov',
      ),
    );
    expect(
      File(
        '${sandbox.path}/artifacts/mutation/leonard_native/full/'
        'leonard_native.lcov',
      ).readAsStringSync(),
      contains('SF:lib/lib/src/native.dart'),
    );
  });

  test('a red baseline prevents mutation execution', () async {
    final Map<String, String> failingEnvironment = <String, String>{
      ...environment,
      'MUTATION_FAIL_BASELINE': '1',
    };

    final ProcessResult result = await _run(
      runner,
      failingEnvironment,
      <String>['full'],
    );

    expect(result.exitCode, 1);
    expect(invocationLog.readAsLinesSync(), <String>['test']);
    expect(
      File(
        '${sandbox.path}/artifacts/mutation/leonard_native/full/console.txt',
      ).existsSync(),
      isFalse,
    );
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
