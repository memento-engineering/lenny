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
          : 'name: $name\ndev_dependencies:\n  mutation_test: ^1.8.0\n',
    );
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
    File(
      '${sandbox.path}/tool/test_impact.dart',
    ).writeAsStringSync('// PATH-backed fake handles this script.\n');
    package('leonard_native');
    package('leonard_contract');
    final Directory bin = Directory('${sandbox.path}/bin')..createSync();
    log = File('${sandbox.path}/calls.txt');
    final File dart = File('${bin.path}/dart')
      ..writeAsStringSync(r'''#!/usr/bin/env bash
printf 'dart %s\n' "$*" >> "$MUTATION_LOG"
if [[ "${1:-}" == test ]]; then exit "${BASELINE_EXIT:-0}"; fi
if [[ "${1:-}" == run && "${2:-}" == */tool/test_impact.dart ]]; then
  output_dir="$4"
  shift 4
  mkdir -p "$output_dir"
  index=0
  for source in "$@"; do
    document="$output_dir/$(printf '%03d' "$index")-input.xml"
    printf '%s\n' \
      '<?xml version="1.0" encoding="UTF-8"?>' \
      "<mutations version=\"1.2\"><files><file>$source</file></files><commands><command>dart test</command></commands></mutations>" \
      > "$document"
    printf '%s\n' "$document"
    index=$((index + 1))
  done
  exit 0
fi
if [[ "${1:-}" == run ]]; then
  [[ " $* " == *" --format all "* ]] && exit "${MUTATION_EXIT:-0}"
  echo "Found 3 mutations"
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
      expect(log.readAsLinesSync(), hasLength(3));
      expect(log.readAsLinesSync().first, contains('--dry --format none'));
      expect(log.readAsStringSync(), isNot(contains('--coverage')));
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
    expect(log.readAsLinesSync(), hasLength(1));
    log.writeAsStringSync('');
    expect((await run(<String>['full', 'leonard_contract'])).exitCode, 0);
    expect(log.readAsLinesSync(), hasLength(3));
    log.writeAsStringSync('');
    expect(
      (await run(<String>['pr', 'leonard_contract', 'lib/a.dart'])).exitCode,
      0,
    );
    expect(log.readAsLinesSync().first, endsWith('lib/a.dart'));
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
    final ProcessResult result = await run(
      <String>['full'],
      env: <String, String>{...environment, 'BASELINE_EXIT': '8'},
    );
    expect(result.exitCode, 8);
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
