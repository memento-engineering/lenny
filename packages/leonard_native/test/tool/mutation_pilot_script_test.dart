library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  late File pilot;
  late File log;
  late Map<String, String> environment;

  void package(String name, {bool flutter = false}) {
    final Directory dir = Directory('${sandbox.path}/packages/$name')
      ..createSync(recursive: true);
    File('${dir.path}/pubspec.yaml').writeAsStringSync(
      flutter
          ? 'name: $name\ndependencies:\n  flutter:\n    sdk: flutter\n'
          : 'name: $name\ndev_dependencies:\n  butcher: ^0.1.0\n',
    );
    if (!flutter) {
      // The exclusion generator runs for real in this sandbox, so the
      // selectable sources have to be real too.
      Directory('${dir.path}/lib').createSync();
      File('${dir.path}/lib/a.dart').writeAsStringSync('const int a = 1;\n');
      File('${dir.path}/lib/b.dart').writeAsStringSync('const int b = 2;\n');
    }
  }

  setUp(() {
    final Directory source = _workspaceRoot();
    sandbox = Directory.systemTemp.createTempSync('mutation-pilot-');
    Directory('${sandbox.path}/.git').createSync();
    Directory('${sandbox.path}/tool').createSync();
    Directory(
      '${sandbox.path}/packages/leonard_cli/lib/assets/tools/leonard',
    ).createSync(recursive: true);
    pilot = File('${sandbox.path}/tool/run_mutation_pilot.sh')
      ..writeAsStringSync(
        File('${source.path}/tool/run_mutation_pilot.sh').readAsStringSync(),
      );
    final String runnerDirectory =
        '${sandbox.path}/packages/leonard_cli/lib/assets/tools/leonard';
    final File
    portableImplementation = File('$runnerDirectory/run_mutation_impl.sh')
      ..writeAsStringSync(
        File(
          '${source.path}/packages/leonard_cli/lib/assets/tools/leonard/run_mutation.sh',
        ).readAsStringSync(),
      );
    final File portable = File('$runnerDirectory/run_mutation.sh')
      ..writeAsStringSync(r'''#!/usr/bin/env bash
if [[ "${LOG_RUNNER_SEAM:-0}" == 1 ]]; then
  printf 'runner %s\n' "$*" >> "$MUTATION_LOG"
fi
exec "$(dirname "$0")/run_mutation_impl.sh" "$@"
''');
    for (final String tool in <String>[
      'butcher_excludes.dart',
      'butcher_report_summary.dart',
    ]) {
      File('${source.path}/tool/$tool').copySync('${sandbox.path}/tool/$tool');
    }
    package('leonard_native');
    package('leonard_contract');
    final Directory bin = Directory('${sandbox.path}/bin')..createSync();
    log = File('${sandbox.path}/calls.txt');
    final File dart = File('${bin.path}/dart')
      ..writeAsStringSync(r'''#!/usr/bin/env bash
printf 'dart %s\n' "$*" >> "$MUTATION_LOG"
if [[ "${1:-}" == test ]]; then exit "${BASELINE_EXIT:-0}"; fi
if [[ "${1:-}" == run && "${2:-}" == */tool/butcher_*.dart ]]; then
  exec "$REAL_DART" "$@"
fi
if [[ "${1:-}" == run && "${2:-}" == butcher:butcher ]]; then
  # butcher verifies its own baseline and writes no report when it is red.
  [[ "${BASELINE_EXIT:-0}" == 0 ]] || exit 70
  output=""
  previous=""
  for argument in "$@"; do
    [[ "$previous" == --output ]] && output="$argument"
    previous="$argument"
  done
  if [[ "$output" == */dry/mutation-report.json ]]; then
    status=NoCoverage
    exit_code="${DRY_EXIT:-0}"
  else
    status=Survived
    exit_code="${MUTATION_EXIT:-0}"
  fi
  printf '{"schemaVersion": "1", "thresholds": {"high": 80, "low": 60}, "files": {"lib/a.dart": {"language": "dart", "source": "x", "mutants": [{"id": "m0", "mutatorName": "equality", "location": {"start": {"line": 1, "column": 1}, "end": {"line": 1, "column": 2}}, "status": "%s", "replacement": "!="}]}}}\n' \
    "$status" > "$output"
  exit "$exit_code"
fi
if [[ "${1:-}" == run && "${2:-}" == mutation_test ]]; then
  [[ " $* " == *" --format all "* ]] && exit "${MUTATION_EXIT:-0}"
  echo "Found 3 mutations"
  [[ " $* " == *" --dry --format none "* ]] && exit "${DRY_EXIT:-0}"
  exit 0
fi
exit 70
''');
    final File flutter = File('${bin.path}/flutter')
      ..writeAsStringSync(r'''#!/usr/bin/env bash
printf 'flutter %s\n' "$*" >> "$MUTATION_LOG"
if [[ "${1:-}" == test ]]; then exit "${BASELINE_EXIT:-0}"; fi
exit 70
''');
    final File flutterRunner =
        File('${sandbox.path}/tool/run_mutation_flutter.sh')..writeAsStringSync(
          File(
            '${source.path}/tool/run_mutation_flutter.sh',
          ).readAsStringSync(),
        );
    for (final File executable in <File>[
      pilot,
      portable,
      portableImplementation,
      flutterRunner,
      dart,
      flutter,
    ]) {
      expect(
        Process.runSync('chmod', <String>['+x', executable.path]).exitCode,
        0,
      );
    }
    environment = <String, String>{
      ...Platform.environment,
      'PATH': '${bin.path}:${Platform.environment['PATH'] ?? ''}',
      'MUTATION_LOG': log.path,
      'REAL_DART': Platform.resolvedExecutable,
    };
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  Future<ProcessResult> run(List<String> args, {Map<String, String>? env}) =>
      Process.run(pilot.path, args, environment: env ?? environment);

  test(
    'Flutter runner forwards exclude strings in dry, pr, and full',
    () async {
      package('leonard_flutter', flutter: true);
      final Map<String, List<String>> modes = <String, List<String>>{
        'dry': <String>['dry', 'leonard_flutter'],
        'pr': <String>['pr', 'leonard_flutter', 'lib/a.dart'],
        'full': <String>['full', 'leonard_flutter'],
      };
      for (final MapEntry<String, List<String>> mode in modes.entries) {
        log.writeAsStringSync('');
        final ProcessResult result = await run(mode.value);
        expect(
          result.exitCode,
          0,
          reason: '${mode.key}: ${result.stdout}\n${result.stderr}',
        );
        final List<String> mutationCalls = log
            .readAsLinesSync()
            .where((String call) => call.startsWith('dart run mutation_test '))
            .toList();
        expect(mutationCalls, hasLength(1), reason: mode.key);
        expect(
          RegExp(
            r'(^| )--exclude-strings($| )',
          ).allMatches(mutationCalls.single),
          hasLength(1),
          reason: '${mode.key}: ${mutationCalls.single}',
        );
      }
    },
  );

  test(
    'defaults to full leonard_native and conditionally supplies coverage',
    () async {
      final ProcessResult first = await run(const <String>[]);
      expect(first.exitCode, 0, reason: first.stderr.toString());
      final List<String> firstCalls = log.readAsLinesSync();
      expect(firstCalls, hasLength(6));
      expect(firstCalls.first, contains('butcher_excludes.dart'));
      expect(
        firstCalls[1],
        contains('/artifacts/mutation/leonard_native/dry/mutation-report.json'),
      );
      expect(firstCalls[4], isNot(contains('--coverage')));
      File('${sandbox.path}/artifacts/coverage/leonard_native.lcov')
        ..createSync(recursive: true)
        ..writeAsStringSync('SF:packages/leonard_native/lib/a.dart\n');
      log.writeAsStringSync('');
      expect((await run(const <String>[])).exitCode, 0);
      expect(log.readAsStringSync(), contains('--coverage'));
      expect(
        log.readAsStringSync(),
        contains('/artifacts/mutation/leonard_native/full/leonard_native.lcov'),
      );
      final String normalizedCoverage = File(
        '${sandbox.path}/artifacts/mutation/leonard_native/full/'
        'leonard_native.lcov',
      ).readAsStringSync();
      expect(normalizedCoverage, 'SF:lib/a.dart\n');
      expect(normalizedCoverage, isNot(contains('SF:lib/lib/a.dart')));
    },
  );

  test('named package and dry/full/pr compatibility', () async {
    expect((await run(<String>['dry', 'leonard_contract'])).exitCode, 0);
    expect(log.readAsLinesSync(), hasLength(3));
    log.writeAsStringSync('');
    expect((await run(<String>['full', 'leonard_contract'])).exitCode, 0);
    expect(log.readAsLinesSync(), hasLength(6));
    log.writeAsStringSync('');
    expect(
      (await run(<String>['pr', 'leonard_contract', 'lib/a.dart'])).exitCode,
      0,
    );
    expect(log.readAsLinesSync().first, endsWith('lib/a.dart'));
  });

  test('pure Dart nightly packages accept counted dry failure', () async {
    for (final String packageName in <String>[
      'leonard_contract',
      'leonard_native',
    ]) {
      log.writeAsStringSync('');
      final ProcessResult result = await run(
        <String>['full', packageName],
        env: <String, String>{...environment, 'DRY_EXIT': '1'},
      );
      expect(
        result.exitCode,
        0,
        reason: '$packageName: ${result.stdout}\n${result.stderr}',
      );
      final List<String> calls = log.readAsLinesSync();
      expect(calls, hasLength(6), reason: packageName);
      expect(calls[1], contains('/$packageName/dry/mutation-report.json'));
      expect(calls[4], contains('/$packageName/full/mutation-report.json'));
      expect(
        File(
          '${sandbox.path}/artifacts/mutation/$packageName/dry/summary.txt',
        ).readAsStringSync(),
        contains('mutants=1'),
        reason: packageName,
      );
    }
  });

  test('test impact routes selected files only through pure Dart', () async {
    final Map<String, String> seamEnvironment = <String, String>{
      ...environment,
      'LOG_RUNNER_SEAM': '1',
    };
    final ProcessResult native = await run(<String>[
      'full',
      'leonard_native',
      'lib/a.dart',
    ], env: seamEnvironment);
    expect(native.exitCode, 0, reason: '${native.stdout}\n${native.stderr}');
    final List<String> nativeSeam = log
        .readAsLinesSync()
        .where((String call) => call.startsWith('runner '))
        .toList();
    expect(nativeSeam, hasLength(1));
    expect(
      RegExp(r'(^| )--test-impact($| )').allMatches(nativeSeam.single),
      hasLength(1),
    );

    log.writeAsStringSync('');
    package('leonard_flutter', flutter: true);
    final ProcessResult flutter = await run(<String>[
      'full',
      'leonard_flutter',
      'lib/a.dart',
    ], env: seamEnvironment);
    expect(flutter.exitCode, 0, reason: '${flutter.stdout}\n${flutter.stderr}');
    expect(log.readAsStringSync(), isNot(contains('--test-impact')));
    expect(
      log.readAsLinesSync().where((String call) => call.startsWith('runner ')),
      isEmpty,
    );
  });

  test('MUTATION_GATE delegates score failure policy', () async {
    final Map<String, String> failing = <String, String>{
      ...environment,
      'MUTATION_EXIT': '27',
    };
    expect((await run(<String>['full'], env: failing)).exitCode, 0);
    expect(
      (await run(
        <String>['full'],
        env: <String, String>{...failing, 'MUTATION_GATE': '1'},
      )).exitCode,
      27,
    );
  });

  test(
    'portable validation covers invalid mode, package, and empty pr',
    () async {
      expect((await run(<String>['nope'])).exitCode, 64);
      expect((await run(<String>['full', 'missing'])).exitCode, 64);
      expect((await run(<String>['pr', 'leonard_native'])).exitCode, 64);
    },
  );

  test('a red baseline remains an unconditional failure', () async {
    // butcher owns the baseline now: a red suite aborts it before any mutant
    // runs and leaves no report, so the sizing check stops the run whether or
    // not gating is on.
    final ProcessResult result = await run(
      <String>['full'],
      env: <String, String>{...environment, 'BASELINE_EXIT': '8'},
    );
    expect(result.exitCode, 70);
    expect(result.stderr, contains('dry sizing failed'));
    expect(log.readAsLinesSync(), hasLength(2));
  });

  test('Flutter packages retain the local flutter mutation path', () async {
    package('leonard_flutter', flutter: true);
    final ProcessResult result = await run(<String>['full', 'leonard_flutter']);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(log.readAsLinesSync().first, 'flutter test');
    expect(log.readAsStringSync(), contains('dart run mutation_test'));
    expect(
      File(
        '${sandbox.path}/artifacts/mutation/leonard_flutter/full/'
        'mutation_rules.xml',
      ).readAsStringSync(),
      contains('flutter test'),
    );

    final Map<String, String> failing = <String, String>{
      ...environment,
      'MUTATION_EXIT': '27',
    };
    expect(
      (await run(<String>['full', 'leonard_flutter'], env: failing)).exitCode,
      0,
    );
    expect(
      (await run(
        <String>['full', 'leonard_flutter'],
        env: <String, String>{...failing, 'MUTATION_GATE': '1'},
      )).exitCode,
      27,
    );
  });
}

Directory _workspaceRoot() {
  Directory current = Directory.current.absolute;
  while (!File('${current.path}/tool/run_mutation_pilot.sh').existsSync()) {
    if (current.parent.path == current.path) {
      throw StateError('workspace not found');
    }
    current = current.parent;
  }
  return current;
}
