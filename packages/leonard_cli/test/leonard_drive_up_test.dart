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

  group(
    'leonard_drive up native dual-path validation',
    () {
      // An on-disk app + native host so the "exists on disk" checks are isolated
      // from the activation/partial checks under test. The native host resolves
      // to the real workspace file; the .app is a stand-in directory.
      final String realHost = p.join(
        packageRoot,
        '..',
        'leonard_native',
        'bin',
        'leonard_native_host.dart',
      );
      final String fixtureApp = p.join(
        packageRoot,
        'test',
        'fixtures',
        'host_target.dart',
      );

      test('native flags + --runner dart is a hard error (exit 64)', () async {
        final ProcessResult r = await run(<String>[
          'up',
          '--runner',
          'dart',
          '-t',
          'bin/host.dart',
          '--udid',
          'SIM-UDID',
          '--app',
          fixtureApp,
          '--native-host',
          realHost,
        ]);
        expect(r.exitCode, 64);
        expect(r.stderr, contains('--runner flutter'));
      });

      test('--udid without --app exits 64 naming --app', () async {
        final ProcessResult r = await run(<String>[
          'up',
          '--runner',
          'flutter',
          '-t',
          'bin/main.dart',
          '--udid',
          'SIM-UDID',
          '--native-host',
          realHost,
        ]);
        expect(r.exitCode, 64);
        expect(r.stderr, contains('--app'));
      });

      test(
        '--udid + --app without a resolvable --native-host exits 64',
        () async {
          final ProcessResult r = await run(<String>[
            'up',
            '--runner',
            'flutter',
            '-t',
            'bin/main.dart',
            '--udid',
            'SIM-UDID',
            '--app',
            fixtureApp,
            '--native-host',
            p.join(packageRoot, 'no', 'such', 'native_host.dart'),
          ]);
          expect(r.exitCode, 64);
          expect(r.stderr, contains('--native-host'));
        },
      );

      test('a nonexistent --app path exits 64', () async {
        final ProcessResult r = await run(<String>[
          'up',
          '--runner',
          'flutter',
          '-t',
          'bin/main.dart',
          '--udid',
          'SIM-UDID',
          '--app',
          p.join(packageRoot, 'no', 'such', 'Runner.app'),
          '--native-host',
          realHost,
        ]);
        expect(r.exitCode, 64);
        expect(r.stderr, contains('--app'));
      });

      test('-d X + --udid Y (Y != X) is a hard error (exit 64)', () async {
        final ProcessResult r = await run(<String>[
          'up',
          '--runner',
          'flutter',
          '-t',
          'bin/main.dart',
          '-d',
          'deviceX',
          '--udid',
          'udidY',
          '--app',
          fixtureApp,
          '--native-host',
          realHost,
        ]);
        expect(r.exitCode, 64);
        expect(r.stderr, contains('--udid'));
      });

      test(
        'Appium at a dead port exits 1 with an actionable message',
        () async {
          // All native preconditions valid, so validation passes and the Appium
          // pre-flight probe runs — a dead port must surface as exit 1 naming
          // Appium + the server URL (NOT a raw StateError).
          final ProcessResult r = await run(<String>[
            'up',
            '--runner',
            'flutter',
            '-t',
            'bin/main.dart',
            '--udid',
            'SIM-UDID',
            '--app',
            fixtureApp,
            '--native-host',
            realHost,
            '--appium-server',
            'http://127.0.0.1:1',
          ]);
          expect(r.exitCode, 1);
          expect(r.stderr, contains('Appium'));
          expect(r.stderr, contains('http://127.0.0.1:1'));
        },
      );
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
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
