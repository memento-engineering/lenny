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
    final File portable =
        File(
          '${sandbox.path}/packages/leonard_cli/lib/assets/tools/leonard/run_mutation.sh',
        )..writeAsStringSync(
          File(
            '${source.path}/packages/leonard_cli/lib/assets/tools/leonard/run_mutation.sh',
          ).readAsStringSync(),
        );
    package('leonard_native');
    package('leonard_contract');
    final Directory bin = Directory('${sandbox.path}/bin')..createSync();
    log = File('${sandbox.path}/calls.txt');
    final File dart = File('${bin.path}/dart')
      ..writeAsStringSync(r'''#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MUTATION_LOG"
if [[ "${1:-}" == test ]]; then exit "${BASELINE_EXIT:-0}"; fi
if [[ "${1:-}" == run ]]; then
  [[ " $* " == *" --format all "* ]] && exit "${MUTATION_EXIT:-0}"
  exit 0
fi
exit 70
''');
    for (final File executable in <File>[pilot, portable, dart]) {
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
    'defaults to full leonard_native and conditionally supplies coverage',
    () async {
      final ProcessResult first = await run(const <String>[]);
      expect(first.exitCode, 0, reason: first.stderr.toString());
      expect(log.readAsLinesSync(), hasLength(3));
      expect(log.readAsLinesSync().first, contains('--dry --format none'));
      expect(log.readAsStringSync(), isNot(contains('--coverage')));
      final File coverage =
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
      expect((await run(<String>['full', 'missing'])).exitCode, 66);
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

  test('Flutter packages are explicitly rejected', () async {
    package('leonard_flutter', flutter: true);
    final ProcessResult result = await run(<String>['full', 'leonard_flutter']);
    expect(result.exitCode, 65);
    expect(result.stderr, contains('pure Dart only'));
  });
}

Directory _workspaceRoot() {
  Directory current = Directory.current.absolute;
  while (!File('${current.path}/tool/run_mutation_pilot.sh').existsSync()) {
    if (current.parent.path == current.path)
      throw StateError('workspace not found');
    current = current.parent;
  }
  return current;
}
