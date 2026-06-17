import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Exit-code smoke tests for the `up` / `down` lifecycle subcommands of
/// leonard_drive. These exercise fast-fail arg validation (which runs before
/// any process spawn), so they boot nothing. The live boot+attach+teardown
/// path is covered in launch_e2e_test.dart.
void main() {
  final String packageRoot = _findPackageRoot();
  final String entrypoint = p.join(packageRoot, 'bin', 'leonard_drive.dart');

  Future<ProcessResult> run(List<String> args) => Process.run(
    Platform.resolvedExecutable,
    <String>['run', entrypoint, ...args],
    workingDirectory: packageRoot,
  );

  group('leonard_drive up/down args', () {
    test('--help lists up and down', () async {
      final ProcessResult r = await run(<String>['--help']);
      expect(r.exitCode, 0, reason: 'stderr: ${r.stderr}');
      expect(r.stdout as String, contains('up'));
      expect(r.stdout as String, contains('down'));
    });

    test('up without --target exits 64', () async {
      final ProcessResult r = await run(<String>['up', '--runner', 'dart']);
      expect(r.exitCode, 64);
      expect(r.stderr, contains('--target'));
    });

    test('up --runner dart with -d is a hard error (no dual mode)', () async {
      final ProcessResult r = await run(<String>[
        'up',
        '--runner',
        'dart',
        '-t',
        'bin/host.dart',
        '-d',
        'iPhone',
      ]);
      expect(r.exitCode, 64);
      expect(r.stderr, contains('--device'));
    });

    test('up with a bad --timeout exits 64', () async {
      final ProcessResult r = await run(<String>[
        'up',
        '--runner',
        'dart',
        '-t',
        'bin/host.dart',
        '--timeout',
        'soon',
      ]);
      expect(r.exitCode, 64);
      expect(r.stderr, contains('--timeout'));
    });

    test('down without --pid-file exits 64', () async {
      final ProcessResult r = await run(<String>['down']);
      expect(r.exitCode, 64);
      expect(r.stderr, contains('--pid-file'));
    });

    test('down on a missing pid-file exits 1', () async {
      final ProcessResult r = await run(<String>[
        'down',
        '--pid-file',
        p.join(packageRoot, 'no', 'such', 'file.pid'),
      ]);
      expect(r.exitCode, 1);
      expect(r.stderr, contains('not found'));
    });
  }, timeout: const Timeout(Duration(seconds: 90)));
}

String _findPackageRoot() {
  Directory dir = Directory.current;
  for (int i = 0; i < 8; i++) {
    final File pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: leonard_cli')) {
      return dir.path;
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return p.normalize(p.join(Directory.current.path, 'packages', 'leonard_cli'));
}
