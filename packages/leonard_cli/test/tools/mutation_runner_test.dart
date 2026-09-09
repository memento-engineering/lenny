// The test-impact cases spawn the runner end to end; under CI coverage
// instrumentation they exceed the 30-second default (lenny#125 coverage job).
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
      'name: portable_package\ndev_dependencies:\n  mutation_test: ^1.8.0\n',
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
    File(
      '${root.path}/tool/test_impact.dart',
    ).copySync('${repo.path}/tool/test_impact.dart');
    Directory('${repo.path}/.dart_tool').createSync();
    File(
      '${root.path}/.dart_tool/package_config.json',
    ).copySync('${repo.path}/.dart_tool/package_config.json');
    final Directory bin = Directory('${repo.path}/bin')..createSync();
    log = File('${repo.path}/calls.txt');
    final File dart = File('${bin.path}/dart');
    dart.writeAsStringSync(r'''#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MUTATION_LOG"
if [[ "${1:-}" == run && "${2:-}" == */tool/test_impact.dart ]]; then
  [[ "${TEST_IMPACT_FAIL:-0}" == 1 ]] && exit 23
  [[ "${TEST_IMPACT_EMPTY:-0}" == 1 ]] && exit 0
  exec "$REAL_DART" "$@"
fi
if [[ "${1:-}" == test ]]; then
  echo baseline
  exit "${BASELINE_EXIT:-0}"
fi
if [[ "${1:-}" == run && "${2:-}" == mutation_test ]]; then
  echo "mutations: $*"
  dry=0
  output=""
  previous=""
  for argument in "$@"; do
    if [[ "$previous" == --rules && -f "$argument" ]]; then
      sed -n 's/.* id="\([^"]*\)".*/semantic mutant: \1/p' "$argument"
    fi
    [[ "$argument" == --dry ]] && dry=1
    [[ "$previous" == --output ]] && output="$argument"
    previous="$argument"
  done
  if (( dry )); then
    [[ "${OMIT_DRY_COUNT:-0}" == 1 ]] || echo "Found ${DRY_MUTATIONS:-3} mutations"
    exit "${DRY_EXIT:-0}"
  fi
  if [[ -n "$output" ]]; then
    echo "--- Results ---"
    for report in mutation-test-report.html mutation-test-report.xml mutation-test-report.junit.xml mutation-test-report.xunit.xml mutation-test-report.md; do
      : > "$output/$report"
    done
    exit "${MUTATION_EXIT:-0}"
  fi
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

  test('vended runner forwards exclude strings in dry, pr, and full', () async {
    final Map<String, List<String>> modes = <String, List<String>>{
      'dry': <String>['dry', package.path],
      'pr': <String>['pr', package.path, '--', 'lib/a.dart'],
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
      final List<String> mutationCalls = log
          .readAsLinesSync()
          .where((String call) => call.startsWith('run mutation_test '))
          .toList();
      expect(mutationCalls, isNotEmpty, reason: mode.key);
      for (final String call in mutationCalls) {
        expect(
          RegExp(r'(^| )--exclude-strings($| )').allMatches(call),
          hasLength(1),
          reason: '${mode.key}: $call',
        );
      }
    }
  });

  test('full sizes before five-format report from any installation', () async {
    final ProcessResult result = await run(<String>['full', package.path]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final List<String> calls = log.readAsLinesSync();
    expect(calls, hasLength(3));
    expect(calls[0], contains('--dry --format none'));
    expect(calls[1], 'test');
    expect(calls[2], contains('--format all --output ${output('full')}'));
    for (final String report in <String>[
      'mutation-test-report.html',
      'mutation-test-report.xml',
      'mutation-test-report.junit.xml',
      'mutation-test-report.xunit.xml',
      'mutation-test-report.md',
    ]) {
      expect(File('${output('full')}/$report').existsSync(), isTrue);
    }
    expect(File('${output('dry')}/console.txt').existsSync(), isTrue);
    expect(File('${output('full')}/console.txt').existsSync(), isTrue);
  });

  test('repeatable custom rules preserve builtin and M1-M8 IDs', () async {
    final String example =
        '${_workspaceRoot().path}/packages/leonard_cli/lib/assets/tools/'
        'leonard/custom_rules.example.xml';
    final ProcessResult result = await run(<String>[
      'dry',
      package.path,
      '--rules',
      example,
      '--rules',
      example,
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final String call = log.readAsStringSync();
    expect(call, contains(' -b '));
    expect(RegExp(RegExp.escape(example)).allMatches(call), hasLength(2));
    final String ledger = File(
      '${output('dry')}/semantic-rules.txt',
    ).readAsStringSync();
    for (int i = 1; i <= 8; i++) {
      expect(ledger, contains('semantic rule: M$i.'));
      expect(
        File('${output('dry')}/console.txt').readAsStringSync(),
        contains('semantic mutant: M$i.'),
      );
    }
  });

  test('coverage is optional and normalized when supplied', () async {
    final File coverage = File('${repo.path}/source.lcov')
      ..writeAsStringSync('SF:packages/portable_package/lib/a.dart\nDA:1,1\n');
    expect(
      (await run(<String>['full', package.path])).stdout,
      contains('no LCOV supplied'),
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
    expect(normalized.readAsStringSync(), contains('SF:lib/a.dart'));
    expect(log.readAsStringSync(), contains('--coverage ${normalized.path}'));
  });

  test('score and baseline failure policy', () async {
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
    Directory(output('full')).deleteSync(recursive: true);
    log.writeAsStringSync('');
    final ProcessResult baseline = await run(
      <String>['full', package.path],
      env: <String, String>{...environment, 'BASELINE_EXIT': '9'},
    );
    expect(baseline.exitCode, 9);
    expect(log.readAsLinesSync(), hasLength(2));
    expect(Directory(output('full')).existsSync(), isFalse);
  });

  test(
    'non-dry sizing accepts counted failure and rejects missing or zero counts',
    () async {
      final ProcessResult counted = await run(
        <String>['pr', package.path, '--', 'lib/a.dart'],
        env: <String, String>{...environment, 'DRY_EXIT': '1'},
      );
      expect(
        counted.exitCode,
        0,
        reason: '${counted.stdout}\n${counted.stderr}',
      );
      expect(log.readAsLinesSync(), hasLength(3));
      expect(
        File('${output('dry')}/console.txt').readAsStringSync(),
        contains('Found 3 mutations'),
      );
      expect(
        File('${output('pr')}/console.txt').readAsStringSync(),
        contains('--- Results ---'),
      );

      log.writeAsStringSync('');
      final ProcessResult missing = await run(
        <String>['pr', package.path, '--', 'lib/a.dart'],
        env: <String, String>{
          ...environment,
          'DRY_EXIT': '1',
          'OMIT_DRY_COUNT': '1',
        },
      );
      expect(missing.exitCode, 70);
      expect(missing.stderr, contains('dry sizing failed'));
      expect(log.readAsLinesSync(), hasLength(1));

      log.writeAsStringSync('');
      final ProcessResult zero = await run(
        <String>['pr', package.path, '--', 'lib/a.dart'],
        env: <String, String>{
          ...environment,
          'DRY_EXIT': '1',
          'DRY_MUTATIONS': '0',
        },
      );
      expect(zero.exitCode, 70);
      expect(zero.stderr, contains('dry sizing failed'));
      expect(log.readAsLinesSync(), hasLength(1));
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

  test('pr forwards package-relative files', () async {
    final ProcessResult result = await run(<String>[
      'pr',
      package.path,
      '--',
      'lib/a.dart',
      'lib/b.dart',
    ]);
    expect(result.exitCode, 0);
    expect(log.readAsLinesSync()[0], endsWith('lib/a.dart lib/b.dart'));
    expect(log.readAsLinesSync()[2], endsWith('lib/a.dart lib/b.dart'));
  });

  test(
    'test-impact passes selective and fallback XML in both phases',
    () async {
      final ProcessResult result = await run(<String>[
        'full',
        package.path,
        '--test-impact',
        '--',
        'lib/imported.dart',
        'lib/unimported.dart',
        'lib/barrel.dart',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');

      final List<String> mutationCalls = log
          .readAsLinesSync()
          .where((String call) => call.startsWith('run mutation_test '))
          .toList();
      expect(mutationCalls, hasLength(2));
      for (final String call in mutationCalls) {
        expect(call, isNot(contains(' lib/imported.dart')));
        expect(call, isNot(contains(' lib/unimported.dart')));
        expect(call, isNot(contains(' lib/barrel.dart')));
        expect(RegExp(r'\.xml($| )').allMatches(call), hasLength(4));
      }

      for (final String phase in <String>['dry', 'full']) {
        final Directory impact = Directory('${output(phase)}/test-impact');
        final List<File> documents =
            impact.listSync().whereType<File>().toList()..sort(
              (File left, File right) => left.path.compareTo(right.path),
            );
        expect(documents, hasLength(3));
        final Map<String, String> bySource = <String, String>{
          for (final File document in documents)
            RegExp(
              r'<file>([^<]+)</file>',
            ).firstMatch(document.readAsStringSync())!.group(1)!: document
                .readAsStringSync(),
        };
        expect(
          bySource['lib/imported.dart'],
          contains('dart test &apos;test/importing_test.dart&apos;'),
        );
        for (final String fallback in <String>[
          'lib/unimported.dart',
          'lib/barrel.dart',
        ]) {
          expect(
            bySource[fallback],
            contains('working-directory=".">dart test</command>'),
          );
        }
        expect(
          File('${output(phase)}/command_rules.xml').readAsStringSync(),
          isNot(contains('<commands>')),
        );
      }
    },
  );

  test('test-impact input failures happen before artifacts', () async {
    final ProcessResult noSources = await run(<String>[
      'full',
      package.path,
      '--test-impact',
    ]);
    expect(noSources.exitCode, 64);
    expect(Directory('${repo.path}/artifacts').existsSync(), isFalse);

    File('${repo.path}/tool/test_impact.dart').deleteSync();
    final ProcessResult missingMapper = await run(<String>[
      'full',
      package.path,
      '--test-impact',
      '--',
      'lib/imported.dart',
    ]);
    expect(missingMapper.exitCode, 66);
    expect(Directory('${repo.path}/artifacts').existsSync(), isFalse);
  });

  test('test-impact rejects failed or empty document generation', () async {
    for (final String variable in <String>[
      'TEST_IMPACT_FAIL',
      'TEST_IMPACT_EMPTY',
    ]) {
      final ProcessResult result = await run(
        <String>[
          'dry',
          package.path,
          '--test-impact',
          '--',
          'lib/imported.dart',
        ],
        env: <String, String>{...environment, variable: '1'},
      );
      expect(result.exitCode, 70, reason: variable);
      expect(result.stderr, contains('test-impact generation'));
    }
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
