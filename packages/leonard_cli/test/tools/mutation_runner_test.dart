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
    final Directory bin = Directory('${repo.path}/bin')..createSync();
    log = File('${repo.path}/calls.txt');
    final File dart = File('${bin.path}/dart');
    dart.writeAsStringSync(r'''#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MUTATION_LOG"
if [[ "${1:-}" == test ]]; then
  echo baseline
  exit "${BASELINE_EXIT:-0}"
fi
if [[ "${1:-}" == run && "${2:-}" == mutation_test ]]; then
  echo "mutations: $*"
  output=""
  previous=""
  for argument in "$@"; do
    if [[ "$previous" == --rules && -f "$argument" ]]; then
      sed -n 's/.* id="\([^"]*\)".*/semantic mutant: \1/p' "$argument"
    fi
    [[ "$previous" == --output ]] && output="$argument"
    previous="$argument"
  done
  if [[ -n "$output" ]]; then
    for report in mutation-test-report.html mutation-test-report.xml mutation-test-report.junit.xml mutation-test-report.xunit.xml mutation-test-report.md; do
      : > "$output/$report"
    done
    exit "${MUTATION_EXIT:-0}"
  fi
  exit "${DRY_EXIT:-0}"
fi
exit 70
''');
    expect(Process.runSync('chmod', <String>['+x', dart.path]).exitCode, 0);
    environment = <String, String>{
      ...Platform.environment,
      'PATH': '${bin.path}:${Platform.environment['PATH'] ?? ''}',
      'MUTATION_LOG': log.path,
    };
  });

  tearDown(() => repo.deleteSync(recursive: true));

  Future<ProcessResult> run(List<String> args, {Map<String, String>? env}) =>
      Process.run(runner.path, args, environment: env ?? environment);

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
