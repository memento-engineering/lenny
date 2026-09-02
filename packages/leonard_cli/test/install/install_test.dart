/// Behavior pins over `bin/install.dart` — the vending entrypoint had no
/// test at all, so the `--copilot` overlay silently rotted onto a repo-root
/// `agents/`+`skills/` layout Copilot no longer reads. These run the real
/// script against a temp dir and assert the layouts each harness actually
/// scans today.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  final String packageRoot = _findPackageRoot();

  Future<ProcessResult> install(List<String> args) => Process.run(
    'dart',
    <String>['bin/install.dart', '--dir', tmp.path, ...args],
    workingDirectory: packageRoot,
  );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('leonard_install_test_');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  test('bare install lands the canonical .agents/ copy only', () async {
    final ProcessResult r = await install(const <String>[]);
    expect(r.exitCode, 0, reason: r.stderr.toString());
    expect(
      File(
        '${tmp.path}/.agents/skills/drive-with-leonard/SKILL.md',
      ).existsSync(),
      isTrue,
    );
    final File mutationReference = File(
      '${tmp.path}/.agents/skills/test-with-leonard/'
      'references/mutation.md',
    );
    expect(mutationReference.existsSync(), isTrue);
    expect(
      mutationReference.readAsStringSync(),
      contains(
        'Before writing an assertion, name the single-line source change',
      ),
    );
    expect(
      File('${tmp.path}/.agents/agents/leonard-drive.agent.md').existsSync(),
      isTrue,
    );
    expect(Directory('${tmp.path}/.github').existsSync(), isFalse);
    expect(Directory('${tmp.path}/.claude').existsSync(), isFalse);
    final File runner = File('${tmp.path}/tool/leonard/run_mutation.sh');
    expect(runner.existsSync(), isTrue);
    expect(
      File('${tmp.path}/tool/leonard/custom_rules.example.xml').existsSync(),
      isTrue,
    );
    if (!Platform.isWindows) {
      expect(Process.runSync('test', <String>['-x', runner.path]).exitCode, 0);
    }
  });

  test(
    '--copilot overlays .github/agents/ and nothing at the repo root',
    () async {
      final ProcessResult r = await install(const <String>['--copilot']);
      expect(r.exitCode, 0, reason: r.stderr.toString());
      final String linkPath =
          '${tmp.path}/.github/agents/leonard-drive.agent.md';
      expect(
        FileSystemEntity.typeSync(linkPath, followLinks: true),
        FileSystemEntityType.file,
        reason: 'the .github/agents overlay must resolve to the vended agent',
      );
      expect(
        File(linkPath).readAsStringSync(),
        contains('name: leonard-drive'),
      );
      // The retired repo-root "Copilot CLI plugin" layout must NOT come back:
      // Copilot stopped scanning it, so a root agents/ or skills/ entry is
      // dead weight polluting the consumer's repo root.
      expect(
        FileSystemEntity.typeSync('${tmp.path}/agents', followLinks: false),
        FileSystemEntityType.notFound,
      );
      expect(
        FileSystemEntity.typeSync('${tmp.path}/skills', followLinks: false),
        FileSystemEntityType.notFound,
      );
      // Skills get no overlay on purpose: .agents/skills/ is a first-class
      // Copilot skill location already.
      expect(Directory('${tmp.path}/.github/skills').existsSync(), isFalse);
    },
  );

  test(
    '--claude overlays .claude/{agents,skills} as resolving links',
    () async {
      final ProcessResult r = await install(const <String>['--claude']);
      expect(r.exitCode, 0, reason: r.stderr.toString());
      expect(
        FileSystemEntity.typeSync(
          '${tmp.path}/.claude/agents/leonard-drive.md',
          followLinks: true,
        ),
        FileSystemEntityType.file,
      );
      expect(
        File(
          '${tmp.path}/.claude/skills/drive-with-leonard/SKILL.md',
        ).existsSync(),
        isTrue,
      );
      final File mutationReference = File(
        '${tmp.path}/.claude/skills/test-with-leonard/'
        'references/mutation.md',
      );
      expect(mutationReference.existsSync(), isTrue);
      expect(
        mutationReference.readAsStringSync(),
        contains('542 mutants, 215 survivors, 60.33% killed'),
      );
    },
  );

  test(
    'install is idempotent — a second run skips, never duplicates',
    () async {
      await install(const <String>['--all']);
      final ProcessResult r = await install(const <String>['--all']);
      expect(r.exitCode, 0, reason: r.stderr.toString());
      expect(r.stdout.toString(), contains('skip'));
      expect(
        r.stdout.toString(),
        contains('skip   tool/leonard/run_mutation.sh'),
      );
      expect(
        Directory('${tmp.path}/.agents/agents')
            .listSync()
            .map((FileSystemEntity e) => e.path.split('/').last)
            .toList(),
        <String>['leonard-drive.agent.md'],
      );
    },
  );

  test('--force restores an overwritten mutation runner', () async {
    await install(const <String>[]);
    final File runner = File('${tmp.path}/tool/leonard/run_mutation.sh');
    runner.writeAsStringSync('overwritten');
    final ProcessResult result = await install(const <String>['--force']);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(runner.readAsStringSync(), startsWith('#!/usr/bin/env bash'));
  });
}

String _findPackageRoot() {
  Directory directory = Directory.current.absolute;
  for (var depth = 0; depth < 8; depth++) {
    for (final Directory candidate in <Directory>[
      directory,
      Directory(p.join(directory.path, 'packages', 'leonard_cli')),
    ]) {
      if (File(p.join(candidate.path, 'bin', 'install.dart')).existsSync() &&
          File(p.join(candidate.path, 'pubspec.yaml')).existsSync()) {
        return candidate.path;
      }
    }
    final Directory parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  throw StateError(
    'could not find leonard_cli package root from ${Directory.current.path}',
  );
}
