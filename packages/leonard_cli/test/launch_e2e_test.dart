/// Live, device-free end-to-end proof of the `up` / `down` lifecycle: boot a
/// pure-Dart `ExplorationHost` target, discover its VM-service ws:// URI,
/// attach an external `tools` driver to it (handshake succeeds), then tear it
/// down via `down`. No Flutter, no device — just `dart`.
@Timeout(Duration(seconds: 150))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final String packageRoot = _findPackageRoot();
  final String driveBin = p.join(packageRoot, 'bin', 'leonard_drive.dart');
  // Relative to packageRoot, which is the spawned runner's working directory.
  final String fixture = p.join('test', 'fixtures', 'host_target.dart');

  test('up boots a pure-Dart host + exposes a ws URI a driver attaches to; '
      'down tears it down', () async {
    final Directory tmp = Directory.systemTemp.createTempSync('leonard_up_e2e');
    final String pidFile = p.join(tmp.path, 'up.pid');
    final Completer<String> wsReady = Completer<String>();
    final Completer<void> shutdownSeen = Completer<void>();
    final List<String> out = <String>[];

    final Process up = await Process.start(
      Platform.resolvedExecutable,
      <String>[
        'run',
        driveBin,
        'up',
        '--runner',
        'dart',
        '-t',
        fixture,
        '--pid-file',
        pidFile,
      ],
      workingDirectory: packageRoot,
    );
    up.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
      String line,
    ) {
      out.add(line);
      Object? obj;
      try {
        obj = jsonDecode(line);
      } on Object {
        return;
      }
      if (obj is! Map) return;
      if (obj['event'] == 'vm_service_ready' && !wsReady.isCompleted) {
        wsReady.complete(obj['ws_uri'] as String);
      }
      if (obj['event'] == 'shutdown' && !shutdownSeen.isCompleted) {
        shutdownSeen.complete();
      }
    });
    // Drain the teed child log so the pipe never blocks.
    up.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((_) {});

    try {
      final String wsUri = await wsReady.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () => throw StateError(
          'no vm_service_ready line. up stdout:\n${out.join('\n')}',
        ),
      );
      expect(Uri.parse(wsUri).isScheme('ws'), isTrue, reason: wsUri);

      // The external brain attaches statelessly and handshakes: the trivial
      // host's `demo` namespace must show up in the manifest.
      final ProcessResult tools = await Process.run(
        Platform.resolvedExecutable,
        <String>['run', driveBin, 'tools', '--vm-uri', wsUri],
        workingDirectory: packageRoot,
      );
      expect(tools.exitCode, 0, reason: 'tools stderr: ${tools.stderr}');
      expect(tools.stdout as String, contains('demo'));

      // down signals the held `up` process; its handler stops the target.
      final ProcessResult down = await Process.run(
        Platform.resolvedExecutable,
        <String>['run', driveBin, 'down', '--pid-file', pidFile],
        workingDirectory: packageRoot,
      );
      expect(down.exitCode, 0, reason: 'down stderr: ${down.stderr}');

      final int code = await up.exitCode.timeout(const Duration(seconds: 30));
      expect(code, 0, reason: 'up should exit cleanly after down');
      await shutdownSeen.future.timeout(const Duration(seconds: 5));
    } finally {
      up.kill(ProcessSignal.sigkill);
      try {
        tmp.deleteSync(recursive: true);
      } on Object {
        // best-effort
      }
    }
  });
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
