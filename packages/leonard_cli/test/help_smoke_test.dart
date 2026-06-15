import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// End-to-end exit-code smoke tests against the CLI binary. Spawns
/// `dart run` as a subprocess so stdout/stderr are real OS streams.
void main() {
  // Resolve the CLI entrypoint relative to the package root regardless
  // of which directory `dart test` was invoked from.
  final String packageRoot = _findPackageRoot();
  final String entrypoint = p.join(packageRoot, 'bin', 'leonard_cli.dart');

  group('leonard_cli smoke', () {
    test('--help exit 0 + AGENTS.md path', () async {
      final ProcessResult r = await Process.run(
        Platform.resolvedExecutable,
        <String>['run', entrypoint, '--help'],
        workingDirectory: packageRoot,
      );
      expect(r.exitCode, 0, reason: 'stderr: ${r.stderr}');
      final String out = r.stdout as String;
      expect(out, contains('leonard_cli/templates/AGENTS.md'));
      expect(out, contains('--vm-uri'));
      expect(out, contains('--goal'));
      expect(out, contains('--model'));
      expect(out, contains('--output'));
      expect(out, contains('--policy'));
      expect(out, contains('--extensions'));
    });

    test('missing --vm-uri exits 64', () async {
      final ProcessResult r = await Process.run(
        Platform.resolvedExecutable,
        <String>['run', entrypoint, '--goal', 'x'],
        workingDirectory: packageRoot,
      );
      expect(r.exitCode, 64);
      expect(r.stderr, contains('--vm-uri'));
    });
  }, timeout: const Timeout(Duration(seconds: 60)));
}

String _findPackageRoot() {
  Directory dir = Directory.current;
  for (int i = 0; i < 8; i++) {
    final File pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      final String contents = pubspec.readAsStringSync();
      if (contents.contains('name: leonard_cli')) {
        return dir.path;
      }
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  // Fallback — assume the conventional checkout layout.
  return p.normalize(p.join(
    Directory.current.path,
    'packages',
    'leonard_cli',
  ));
}
