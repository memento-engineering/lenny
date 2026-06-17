import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Exit-code smoke tests for the `screenshot` subcommand of leonard_drive.
/// These exercise the fast-fail arg validation (which runs before any VM
/// connection), so they need no running app. The capture path itself is
/// covered live against a real instrumented app, not here.
void main() {
  final String packageRoot = _findPackageRoot();
  final String entrypoint = p.join(packageRoot, 'bin', 'leonard_drive.dart');

  Future<ProcessResult> run(List<String> args) => Process.run(
    Platform.resolvedExecutable,
    <String>['run', entrypoint, ...args],
    workingDirectory: packageRoot,
  );

  group('leonard_drive screenshot args', () {
    test('--help lists the screenshot subcommand', () async {
      final ProcessResult r = await run(<String>['--help']);
      expect(r.exitCode, 0, reason: 'stderr: ${r.stderr}');
      expect(r.stdout as String, contains('screenshot'));
      expect(r.stdout as String, contains('--out'));
    });

    test('screenshot without --vm-uri exits 64', () async {
      final ProcessResult r = await run(<String>['screenshot', '--out', 'x.png']);
      expect(r.exitCode, 64);
      expect(r.stderr, contains('--vm-uri'));
    });

    test('screenshot without --out exits 64 (before any connect)', () async {
      final ProcessResult r = await run(<String>[
        'screenshot',
        '--vm-uri',
        'ws://127.0.0.1:9/ws',
      ]);
      expect(r.exitCode, 64);
      expect(r.stderr, contains('--out'));
    });
  }, timeout: const Timeout(Duration(seconds: 60)));
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
