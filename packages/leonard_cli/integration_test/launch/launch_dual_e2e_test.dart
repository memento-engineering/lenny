/// Live, hardware-gated dual-channel e2e for `leonard_drive up`/`down`: boot a
/// Flutter target AND the leonard_native host against the SAME sim, parse the
/// extended `vm_service_ready` line, drive a SINGLE channel against
/// `native_endpoint` (gated on `LEONARD_HOST_READY`), then tear BOTH down via
/// one `--pid-file`. Modeled on `launch_e2e_test.dart` + the native package's
/// `native_host_e2e_test.dart`.
///
/// Self-skips (one skipped test, no new tag — the house rule) when the live
/// tier is absent. The live tier needs ALL of:
///
///   * a reachable Appium server (default `http://127.0.0.1:4723`, override via
///     `LEONARD_NATIVE_APPIUM_SERVER`);
///   * an already-booted iOS simulator udid in `LEONARD_NATIVE_SIM_UDID`;
///   * a built `Runner.app` path in `LEONARD_NATIVE_APP`;
///   * the Flutter project root (the cwd `flutter run` needs) in
///     `LEONARD_NATIVE_FLUTTER_PROJECT`;
///   * a Flutter entrypoint (relative to that project, or absolute) in
///     `LEONARD_NATIVE_FLUTTER_TARGET`.
///
/// `up` is launched with the Flutter project as its working directory (so the
/// spawned `flutter run` resolves the project); the absolute `--native-host`
/// and the absolute `leonard_drive.dart` entrypoint resolve their own package
/// configs from their file locations, independent of that cwd.
///
/// The operator provisions Appium + the booted sim; `up` boots neither (attach
/// default). The drive STOPS before SIGN IN (m5 owns the Auth0 round-trip):
/// it proves both channels come UP and DOWN, NOT authentication. This is a
/// SINGLE-host handshake against `native_endpoint` only — it does NOT attach a
/// second session to `flutter_ws_uri`, merge fragments, or route by namespace
/// (all m3).
@Timeout(Duration(seconds: 300))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _serverEnv = 'LEONARD_NATIVE_APPIUM_SERVER';
const String _udidEnv = 'LEONARD_NATIVE_SIM_UDID';
const String _appEnv = 'LEONARD_NATIVE_APP';
const String _flutterProjectEnv = 'LEONARD_NATIVE_FLUTTER_PROJECT';
const String _flutterTargetEnv = 'LEONARD_NATIVE_FLUTTER_TARGET';

const String _defaultServer = 'http://127.0.0.1:4723';

String _appiumServer() =>
    Platform.environment[_serverEnv]?.trim().isNotEmpty == true
    ? Platform.environment[_serverEnv]!.trim()
    : _defaultServer;

/// True when a live Appium server answers `GET /status` (W3C health check).
/// Async — the reachability probe runs INSIDE the test body. An HTTP round-trip
/// cannot be done from a synchronous main()-time gate: `sleep` blocks the
/// isolate's event loop, so the request would never complete (it would always
/// time out and the e2e would always self-skip, even with Appium running).
Future<bool> _appiumReachable(String server) async {
  try {
    final Uri base = Uri.parse(server);
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final HttpClientRequest req = await client.getUrl(
        base.replace(path: '${base.path}/status'),
      );
      final HttpClientResponse res = await req.close().timeout(
        const Duration(seconds: 5),
      );
      await res.drain<void>(null);
      return res.statusCode >= 200 && res.statusCode < 500;
    } finally {
      client.close(force: true);
    }
  } on Object {
    return false;
  }
}

/// Env-only skip reason (synchronous): the udid/app/flutter-target must be set
/// + the `.app` must exist. Appium reachability is probed asynchronously inside
/// the test body (see [_appiumReachable]).
String? _envSkipReason() {
  final String? udid = Platform.environment[_udidEnv];
  final String? app = Platform.environment[_appEnv];
  final String? flutterProject = Platform.environment[_flutterProjectEnv];
  final String? flutterTarget = Platform.environment[_flutterTargetEnv];
  if (udid == null ||
      udid.isEmpty ||
      app == null ||
      app.isEmpty ||
      flutterProject == null ||
      flutterProject.isEmpty ||
      flutterTarget == null ||
      flutterTarget.isEmpty) {
    return '$_udidEnv + $_appEnv + $_flutterProjectEnv + $_flutterTargetEnv '
        'must point at a booted iOS sim + a built .app + a Flutter project '
        'root + an entrypoint — live dual launch e2e skipped';
  }
  if (!File(app).existsSync() && !Directory(app).existsSync()) {
    return '$_appEnv ($app) does not exist — live dual launch e2e skipped';
  }
  if (!File(p.join(flutterProject, 'pubspec.yaml')).existsSync()) {
    return '$_flutterProjectEnv ($flutterProject) is not a Flutter project '
        '(no pubspec.yaml) — live dual launch e2e skipped';
  }
  return null;
}

/// Locate the native host runner relative to the cwd, mirroring
/// `native_host_e2e_test._hostScript()`'s dual-path resolver (repo root vs
/// package dir).
String _hostScript(String packageRoot) {
  final List<String> candidates = <String>[
    p.join(
      packageRoot,
      '..',
      'leonard_native',
      'bin',
      'leonard_native_host.dart',
    ),
    'bin/leonard_native_host.dart',
    'packages/leonard_native/bin/leonard_native_host.dart',
  ];
  for (final String c in candidates) {
    if (File(c).existsSync()) return c;
  }
  throw StateError(
    'cannot locate leonard_native_host.dart from ${Directory.current.path}',
  );
}

void main() {
  final String? envSkip = _envSkipReason();
  final String packageRoot = _findPackageRoot();
  final String driveBin = p.join(packageRoot, 'bin', 'leonard_drive.dart');

  test('up boots BOTH channels against one sim; down tears both down', () async {
    if (envSkip != null) {
      markTestSkipped(envSkip);
      return;
    }
    final String server = _appiumServer();
    if (!await _appiumReachable(server)) {
      markTestSkipped(
        'no Appium server at $server — live dual launch e2e skipped',
      );
      return;
    }
    final String udid = Platform.environment[_udidEnv]!;
    final String app = Platform.environment[_appEnv]!;
    final String flutterProject = Platform.environment[_flutterProjectEnv]!;
    final String flutterTarget = Platform.environment[_flutterTargetEnv]!;
    final String nativeHost = _hostScript(packageRoot);

    final Directory tmp = Directory.systemTemp.createTempSync(
      'leonard_dual_e2e',
    );
    final String pidFile = p.join(tmp.path, 'up.pid');
    final String uriFile = p.join(tmp.path, 'up.uris');
    final Completer<Map<String, dynamic>> ready =
        Completer<Map<String, dynamic>>();
    final Completer<void> shutdownSeen = Completer<void>();
    final List<String> out = <String>[];

    final Process up = await Process.start(
      Platform.resolvedExecutable,
      <String>[
        'run',
        driveBin,
        'up',
        '--runner',
        'flutter',
        '-t',
        flutterTarget,
        '--udid',
        udid,
        '--app',
        app,
        '--native-host',
        nativeHost,
        '--appium-server',
        server,
        '--pid-file',
        pidFile,
        '--uri-file',
        uriFile,
        // `up` runs from the Flutter project so the spawned `flutter run`
        // resolves it; the absolute driveBin + --native-host resolve their
        // own package configs from their file locations, not this cwd.
      ],
      workingDirectory: flutterProject,
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
      if (obj['event'] == 'vm_service_ready' && !ready.isCompleted) {
        ready.complete(obj.cast<String, dynamic>());
      }
      if (obj['event'] == 'shutdown' && !shutdownSeen.isCompleted) {
        shutdownSeen.complete();
      }
    });
    // Drain stderr so the teed child log never blocks the pipe.
    up.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((_) {});

    try {
      final Map<String, dynamic> envelope = await ready.future.timeout(
        const Duration(seconds: 240),
        onTimeout: () => throw StateError(
          'no vm_service_ready line. up stdout:\n${out.join('\n')}',
        ),
      );

      // AC7: the extended envelope carries both endpoints + the shared device.
      final String flutterWs = envelope['flutter_ws_uri'] as String;
      final String nativeEndpoint = envelope['native_endpoint'] as String;
      expect(Uri.parse(flutterWs).isScheme('ws'), isTrue, reason: flutterWs);
      expect(
        Uri.parse(nativeEndpoint).isScheme('ws'),
        isTrue,
        reason: nativeEndpoint,
      );
      expect(envelope['device_id'], udid);
      // Back-compat: ws_uri stays the Flutter/primary channel.
      expect(envelope['ws_uri'], flutterWs);

      // AC7: --uri-file holds both lines, FLUTTER FIRST.
      final List<String> uriLines = (await File(
        uriFile,
      ).readAsString()).trim().split('\n');
      expect(uriLines.length, 2, reason: 'uri-file: $uriLines');
      expect(uriLines[0], flutterWs);
      expect(uriLines[1], nativeEndpoint);

      // AC8/AC12: single-channel handshake against native_endpoint only (m3
      // boundary — do NOT attach to flutter_ws_uri, merge, or route). Seeing
      // the `native` namespace proves the Appium session is live (gated on
      // LEONARD_HOST_READY).
      final ProcessResult tools = await Process.run(
        Platform.resolvedExecutable,
        <String>['run', driveBin, 'tools', '--vm-uri', nativeEndpoint],
        workingDirectory: packageRoot,
      );
      expect(tools.exitCode, 0, reason: 'tools stderr: ${tools.stderr}');
      expect(tools.stdout as String, contains('native'));

      // AC9: down tears BOTH channels down via the single pid-file.
      final ProcessResult down = await Process.run(
        Platform.resolvedExecutable,
        <String>['run', driveBin, 'down', '--pid-file', pidFile],
        workingDirectory: packageRoot,
      );
      expect(down.exitCode, 0, reason: 'down stderr: ${down.stderr}');

      final int code = await up.exitCode.timeout(const Duration(seconds: 60));
      expect(code, 0, reason: 'up should exit cleanly after down');
      await shutdownSeen.future.timeout(const Duration(seconds: 10));
      // STOP before SIGN IN — m5 owns sign-in / callback / resume-on-Flutter.
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
