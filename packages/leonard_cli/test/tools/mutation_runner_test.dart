// Every case spawns the runner end to end; under CI coverage instrumentation
// they exceed the 30-second default (lenny#125 coverage job).
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory repo;
  late Directory package;
  late File runner;
  late File log;
  late Map<String, String> environment;

  String output(String phase) =>
      '${repo.path}/artifacts/mutation/portable_package/$phase';

  setUp(() {
    final Directory root = _workspaceRoot();
    runner = File(
      '${root.path}/packages/leonard_cli/lib/assets/tools/leonard/run_mutation.sh',
    );
    repo = Directory(
      Directory.systemTemp
          .createTempSync('portable-mutation-')
          .resolveSymbolicLinksSync(),
    );
    Directory('${repo.path}/.git').createSync();
    package = Directory('${repo.path}/nested/package')
      ..createSync(recursive: true);
    File('${package.path}/pubspec.yaml').writeAsStringSync(
      'name: portable_package\ndev_dependencies:\n  butcher: ^0.1.0\n',
    );
    Directory('${package.path}/lib').createSync();
    File(
      '${package.path}/lib/imported.dart',
    ).writeAsStringSync('const a = 1;\n');
    File(
      '${package.path}/lib/unimported.dart',
    ).writeAsStringSync('const b = 2;\n');
    File(
      '${package.path}/lib/barrel.dart',
    ).writeAsStringSync("export 'imported.dart';\n");
    Directory('${package.path}/test').createSync();
    File('${package.path}/test/importing_test.dart').writeAsStringSync(
      "import 'package:portable_package/imported.dart';\nvoid main() {}\n",
    );
    Directory('${repo.path}/tool').createSync();
    for (final String tool in <String>[
      'butcher_excludes.dart',
      'butcher_report_summary.dart',
    ]) {
      File('${root.path}/tool/$tool').copySync('${repo.path}/tool/$tool');
    }
    Directory('${repo.path}/.dart_tool').createSync();
    File(
      '${root.path}/.dart_tool/package_config.json',
    ).copySync('${repo.path}/.dart_tool/package_config.json');
    final Directory bin = Directory('${repo.path}/bin')..createSync();
    log = File('${repo.path}/calls.txt');
    final File dart = File('${bin.path}/dart');
    dart.writeAsStringSync(r'''#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MUTATION_LOG"
if [[ "${1:-}" == run && "${2:-}" == */tool/butcher_*.dart ]]; then
  exec "$REAL_DART" "$@"
fi
if [[ "${1:-}" == run && "${2:-}" == butcher:butcher ]]; then
  echo "butcher: $*"
  output=""
  previous=""
  for argument in "$@"; do
    [[ "$previous" == --output ]] && output="$argument"
    previous="$argument"
  done
  if [[ "$output" == */dry/mutation-report.json ]]; then
    count="${DRY_MUTANTS:-3}"
    status=NoCoverage
    [[ "${OMIT_DRY_REPORT:-0}" == 1 ]] && count=-1
    exit_code="${DRY_EXIT:-0}"
  else
    count="${FULL_MUTANTS:-3}"
    status=Survived
    exit_code="${MUTATION_EXIT:-0}"
  fi
  if (( count >= 0 )); then
    {
      printf '{\n  "schemaVersion": "1",\n  "thresholds": {"high": 80, "low": 60},\n'
      printf '  "files": {\n    "lib/imported.dart": {\n'
      printf '      "language": "dart",\n      "source": "const a = 1;\\n",\n'
      printf '      "mutants": ['
      for (( index = 0; index < count; index++ )); do
        (( index )) && printf ','
        printf '\n        {"id": "m%s", "mutatorName": "equality", ' "$index"
        printf '"location": {"start": {"line": 1, "column": 1}, "end": {"line": 1, "column": 2}}, '
        printf '"status": "%s", "replacement": "!="}' "$status"
      done
      printf '\n      ]\n    }\n  }\n}\n'
    } > "$output"
  fi
  exit "$exit_code"
fi
exit 70
''');
    expect(Process.runSync('chmod', <String>['+x', dart.path]).exitCode, 0);
    environment = <String, String>{
      ...Platform.environment,
      'PATH': '${bin.path}:${Platform.environment['PATH'] ?? ''}',
      'MUTATION_LOG': log.path,
      'REAL_DART': Platform.resolvedExecutable,
    };
  });

  tearDown(() => repo.deleteSync(recursive: true));

  Future<ProcessResult> run(List<String> args, {Map<String, String>? env}) =>
      Process.run(runner.path, args, environment: env ?? environment);

  List<String> butcherCalls() => log
      .readAsLinesSync()
      .where((String call) => call.startsWith('run butcher:butcher '))
      .toList();

  test('the runner drives butcher in dry, pr, and full', () async {
    final Map<String, List<String>> modes = <String, List<String>>{
      'dry': <String>['dry', package.path],
      'pr': <String>['pr', package.path, '--', 'lib/imported.dart'],
      'full': <String>['full', package.path],
    };
    for (final MapEntry<String, List<String>> mode in modes.entries) {
      log.writeAsStringSync('');
      final ProcessResult result = await run(mode.value);
      expect(
        result.exitCode,
        0,
        reason: '${mode.key}: ${result.stdout}\n${result.stderr}',
      );
      expect(butcherCalls(), isNotEmpty, reason: mode.key);
      expect(
        butcherCalls().first,
        contains('--coverage ${output('dry')}/empty.lcov'),
        reason: '${mode.key}: the dry phase sizes without evaluating',
      );
      expect(
        File('${package.path}/butcher.yaml').existsSync(),
        isFalse,
        reason: '${mode.key}: the generated configuration outlives no run',
      );
    }
  });

  test('full sizes before the scored phase and writes both reports', () async {
    final ProcessResult result = await run(<String>['full', package.path]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');

    final List<String> calls = butcherCalls();
    expect(calls, hasLength(2));
    expect(
      calls[0],
      contains('--output ${output('dry')}/mutation-report.json'),
    );
    expect(
      calls[1],
      contains('--output ${output('full')}/mutation-report.json'),
    );
    for (final String phase in <String>['dry', 'full']) {
      for (final String artifact in <String>[
        'console.txt',
        'mutation-report.json',
        'mutation-report.md',
        'summary.txt',
        'excludes.txt',
      ]) {
        expect(
          File('${output(phase)}/$artifact').existsSync(),
          isTrue,
          reason: '$phase/$artifact',
        );
      }
    }
    expect(
      File('${output('full')}/summary.txt').readAsStringSync(),
      allOf(contains('mutants=3'), contains('survived=3'), contains('msi=')),
    );
    expect(
      File('${output('full')}/mutation-report.md').readAsStringSync(),
      contains('## Surviving mutants in lib/imported.dart'),
    );
  });

  test('custom rules are refused, because butcher has no rules seam', () async {
    final File rules = File('${repo.path}/rules.xml')
      ..writeAsStringSync('<mutations/>\n');

    final ProcessResult result = await run(<String>[
      'dry',
      package.path,
      '--rules',
      rules.path,
    ]);

    expect(result.exitCode, 65);
    expect(result.stderr, contains('retired regex engine'));
    expect(Directory('${repo.path}/artifacts').existsSync(), isFalse);
  });

  test('coverage is optional and normalized when supplied', () async {
    final File coverage = File('${repo.path}/source.lcov')
      ..writeAsStringSync(
        'SF:packages/portable_package/lib/imported.dart\nDA:1,1\n',
      );
    expect(
      (await run(<String>['full', package.path])).stdout,
      contains('butcher collects its own coverage'),
    );
    log.writeAsStringSync('');
    final ProcessResult covered = await run(<String>[
      'full',
      package.path,
      '--coverage',
      coverage.path,
    ]);
    expect(covered.exitCode, 0);
    final File normalized = File('${output('full')}/portable_package.lcov');
    expect(normalized.readAsStringSync(), contains('SF:lib/imported.dart'));
    expect(butcherCalls()[1], contains('--coverage ${normalized.path}'));
  });

  test('score and red-baseline failure policy', () async {
    final Map<String, String> mutationFailure = <String, String>{
      ...environment,
      'MUTATION_EXIT': '23',
    };
    expect(
      (await run(<String>[
        'full',
        package.path,
      ], env: mutationFailure)).exitCode,
      0,
    );
    expect(
      (await run(<String>[
        'full',
        package.path,
        '--gate',
      ], env: mutationFailure)).exitCode,
      23,
    );

    // butcher verifies its own baseline and aborts on a red suite without
    // writing a report, so the run stops before the scored phase whether or
    // not gating is on.
    Directory(output('full')).deleteSync(recursive: true);
    log.writeAsStringSync('');
    final ProcessResult baseline = await run(
      <String>['full', package.path],
      env: <String, String>{
        ...environment,
        'DRY_EXIT': '70',
        'OMIT_DRY_REPORT': '1',
      },
    );
    expect(baseline.exitCode, 70);
    expect(baseline.stderr, contains('dry sizing failed'));
    expect(butcherCalls(), hasLength(1));
    expect(Directory(output('full')).existsSync(), isFalse);
  });

  test(
    'non-dry sizing accepts counted failure and rejects missing or zero counts',
    () async {
      final ProcessResult counted = await run(
        <String>['pr', package.path, '--', 'lib/imported.dart'],
        env: <String, String>{...environment, 'DRY_EXIT': '1'},
      );
      expect(
        counted.exitCode,
        0,
        reason: '${counted.stdout}\n${counted.stderr}',
      );
      expect(butcherCalls(), hasLength(2));
      expect(
        File('${output('dry')}/summary.txt').readAsStringSync(),
        contains('mutants=3'),
      );

      log.writeAsStringSync('');
      final ProcessResult missing = await run(
        <String>['pr', package.path, '--', 'lib/imported.dart'],
        env: <String, String>{
          ...environment,
          'DRY_EXIT': '1',
          'OMIT_DRY_REPORT': '1',
        },
      );
      expect(missing.exitCode, 70);
      expect(missing.stderr, contains('dry sizing failed'));
      expect(butcherCalls(), hasLength(1));

      log.writeAsStringSync('');
      final ProcessResult zero = await run(
        <String>['pr', package.path, '--', 'lib/imported.dart'],
        env: <String, String>{
          ...environment,
          'DRY_EXIT': '1',
          'DRY_MUTANTS': '0',
        },
      );
      expect(zero.exitCode, 70);
      expect(zero.stderr, contains('dry sizing failed'));
      expect(butcherCalls(), hasLength(1));
    },
  );

  test('standalone dry retains reporting and gate policy', () async {
    final Map<String, String> dryFailure = <String, String>{
      ...environment,
      'DRY_EXIT': '1',
    };
    final ProcessResult reporting = await run(<String>[
      'dry',
      package.path,
    ], env: dryFailure);
    expect(reporting.exitCode, 0);
    expect(reporting.stdout, contains('Reporting only (gating off).'));

    final ProcessResult gated = await run(<String>[
      'dry',
      package.path,
      '--gate',
    ], env: dryFailure);
    expect(gated.exitCode, 1);
    expect(gated.stdout, isNot(contains('Reporting only (gating off).')));
  });

  test('a per-file selection becomes a generated exclude list', () async {
    final ProcessResult result = await run(<String>[
      'pr',
      package.path,
      '--',
      'lib/imported.dart',
      'lib/barrel.dart',
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final List<String> excludeCalls = log
        .readAsLinesSync()
        .where((String call) => call.contains('butcher_excludes.dart'))
        .toList();
    expect(excludeCalls, hasLength(2));
    for (final String call in excludeCalls) {
      expect(call, endsWith('lib/imported.dart lib/barrel.dart'));
    }
    expect(
      File('${output('pr')}/excludes.txt').readAsStringSync(),
      contains('1 of 3 sources excluded'),
    );
    expect(File('${package.path}/butcher.yaml').existsSync(), isFalse);
  });

  test('an empty selection leaves the whole library in scope', () async {
    final ProcessResult result = await run(<String>['full', package.path]);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(
      File('${output('full')}/excludes.txt').readAsStringSync(),
      contains('the whole library is in scope'),
    );
    expect(File('${package.path}/butcher.yaml').existsSync(), isFalse);
  });

  test('a hand-authored butcher.yaml stops the run untouched', () async {
    final File authored = File('${package.path}/butcher.yaml')
      ..writeAsStringSync('exclude:\n  - lib/barrel.dart\n');

    final ProcessResult result = await run(<String>[
      'pr',
      package.path,
      '--',
      'lib/imported.dart',
    ]);

    expect(result.exitCode, 70);
    expect(result.stderr, contains('exclusion generation failed'));
    expect(authored.readAsStringSync(), contains('lib/barrel.dart'));
  });

  test('test-impact hands routing to butcher instead of an lcov', () async {
    final File coverage = File('${repo.path}/source.lcov')
      ..writeAsStringSync(
        'SF:packages/portable_package/lib/imported.dart\nDA:1,1\n',
      );

    final ProcessResult result = await run(<String>[
      'full',
      package.path,
      '--coverage',
      coverage.path,
      '--test-impact',
      '--',
      'lib/imported.dart',
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('butcher collects that itself'));
    expect(butcherCalls()[1], isNot(contains('--coverage')));
    expect(
      File('${output('full')}/portable_package.lcov').existsSync(),
      isFalse,
    );
  });

  test('test-impact without sources fails before artifacts', () async {
    final ProcessResult noSources = await run(<String>[
      'full',
      package.path,
      '--test-impact',
    ]);
    expect(noSources.exitCode, 64);
    expect(Directory('${repo.path}/artifacts').existsSync(), isFalse);
  });

  test('invalid inputs fail before full artifacts', () async {
    Future<void> fails(List<String> args, int code) async {
      final ProcessResult result = await run(args);
      expect(
        result.exitCode,
        code,
        reason: 'args=$args stderr=${result.stderr}',
      );
      expect(Directory('${repo.path}/artifacts').existsSync(), isFalse);
    }

    await fails(<String>['wat', package.path], 64);
    await fails(<String>['full'], 64);
    await fails(<String>['pr', package.path], 64);
    await fails(<String>['full', package.path, '--wat'], 64);
    await fails(<String>['full', '${repo.path}/missing'], 66);
    await fails(<String>[
      'full',
      package.path,
      '--repo-root',
      '${repo.path}/missing',
    ], 66);
    await fails(<String>[
      'full',
      package.path,
      '--rules',
      '${repo.path}/x',
    ], 66);
    await fails(<String>[
      'full',
      package.path,
      '--coverage',
      '${repo.path}/x',
    ], 66);
    File('${repo.path}/tool/butcher_excludes.dart').deleteSync();
    await fails(<String>['full', package.path], 66);
    final Directory unnamed = Directory('${repo.path}/unnamed')..createSync();
    File('${unnamed.path}/pubspec.yaml').writeAsStringSync('version: 1.0.0\n');
    await fails(<String>['full', unnamed.path], 65);
    File(
      '${unnamed.path}/pubspec.yaml',
    ).writeAsStringSync('name: ../../escape\n');
    await fails(<String>['full', unnamed.path], 65);
  });

  test('Flutter SDK packages are rejected', () async {
    File('${package.path}/pubspec.yaml').writeAsStringSync(
      'name: portable_package\ndependencies:\n  flutter:\n    sdk: flutter\n',
    );
    final ProcessResult result = await run(<String>['full', package.path]);
    expect(result.exitCode, 65);
    expect(result.stderr, contains('pure Dart only'));
    expect(Directory('${repo.path}/artifacts').existsSync(), isFalse);
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
