/// Live, hardware-gated dual-channel e2e for `leonard_drive drive-dual`
/// (m3, `lenny-qxx.3`): boot a Flutter target AND the leonard_native host
/// against the SAME sim via `up` (reusing m4's `up`/`_upDual`), then attach a
/// `MultiHostSession` to BOTH endpoints and prove m3's three jobs against the
/// LIVE dual session:
///
///   * `drive-dual tools`  → the MERGED manifest carries `core` AND `native`
///     (the handshake union — proves the native channel is advertised, §3).
///   * `drive-dual observe` → the MERGED observation carries `core` (Flutter)
///     AND `extensions.native` (native) side by side (§5).
///   * `drive-dual invoke --tool native.tap …` → routed to the native channel,
///     returning a tool result (§4).
///
/// Self-skips (one skipped test, no new tag — the house rule) when the live
/// tier is absent. The live tier needs ALL of:
///
///   * a reachable Appium server (default `http://127.0.0.1:4723`, override via
///     `LEONARD_NATIVE_APPIUM_SERVER`);
///   * an already-booted iOS simulator udid in `LEONARD_NATIVE_SIM_UDID`;
///   * a built `Runner.app` path in `LEONARD_NATIVE_APP`;
///   * the Flutter project root in `LEONARD_NATIVE_FLUTTER_PROJECT`;
///   * a Flutter entrypoint in `LEONARD_NATIVE_FLUTTER_TARGET`.
///
/// The env gate is synchronous at `main()`-time; Appium reachability is probed
/// asynchronously INSIDE the test body (a `sleep`-based sync probe would
/// deadlock the isolate and always self-skip — m4's rule). The operator
/// provisions Appium + the booted sim; `up` boots neither (attach default).
///
/// The drive STOPS before SIGN IN — m5 owns the Auth0 round-trip
/// (sign-in / consent / callback / resume-on-Flutter). This e2e proves the
/// brain can attach BOTH channels, see BOTH fragments, and route a tool to the
/// right host; it does NOT authenticate.
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
        'root + an entrypoint — live drive-dual e2e skipped';
  }
  if (!File(app).existsSync() && !Directory(app).existsSync()) {
    return '$_appEnv ($app) does not exist — live drive-dual e2e skipped';
  }
  if (!File(p.join(flutterProject, 'pubspec.yaml')).existsSync()) {
    return '$_flutterProjectEnv ($flutterProject) is not a Flutter project '
        '(no pubspec.yaml) — live drive-dual e2e skipped';
  }
  return null;
}

/// Locate the native host runner relative to the cwd, mirroring
/// `launch_dual_e2e_test._hostScript()`'s dual-path resolver.
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

  test('drive-dual attaches BOTH channels, merges, and routes', () async {
    if (envSkip != null) {
      markTestSkipped(envSkip);
      return;
    }
    final String server = _appiumServer();
    if (!await _appiumReachable(server)) {
      markTestSkipped(
        'no Appium server at $server — live drive-dual e2e skipped',
      );
      return;
    }
    final String udid = Platform.environment[_udidEnv]!;
    final String app = Platform.environment[_appEnv]!;
    final String flutterProject = Platform.environment[_flutterProjectEnv]!;
    final String flutterTarget = Platform.environment[_flutterTargetEnv]!;
    final String nativeHost = _hostScript(packageRoot);

    final Directory tmp = Directory.systemTemp.createTempSync(
      'leonard_drive_dual_e2e',
    );
    final String pidFile = p.join(tmp.path, 'up.pid');
    final String uriFile = p.join(tmp.path, 'up.uris');
    final Completer<Map<String, dynamic>> ready =
        Completer<Map<String, dynamic>>();
    final List<String> out = <String>[];

    final Process up =
        await Process.start(Platform.resolvedExecutable, <String>[
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
        ], workingDirectory: flutterProject);
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
    });
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
      final String flutterWs = envelope['flutter_ws_uri'] as String;
      final String nativeEndpoint = envelope['native_endpoint'] as String;

      // AC4/AC12: drive-dual tools — the MERGED manifest carries core AND
      // native (the handshake union; the native channel is advertised).
      final ProcessResult tools =
          await Process.run(Platform.resolvedExecutable, <String>[
            'run',
            driveBin,
            'drive-dual',
            'tools',
            '--flutter-uri',
            flutterWs,
            '--native-uri',
            nativeEndpoint,
          ], workingDirectory: packageRoot);
      expect(tools.exitCode, 0, reason: 'tools stderr: ${tools.stderr}');
      final Map<String, dynamic> toolsJson =
          (jsonDecode(tools.stdout as String) as Map).cast<String, dynamic>();
      final Set<String> namespaces = <String>{
        for (final Object? e in toolsJson['namespaces'] as List)
          (e as Map)['namespace'] as String,
      };
      expect(namespaces, contains('core'), reason: 'merged: $namespaces');
      expect(namespaces, contains('native'), reason: 'merged: $namespaces');

      // AC12: drive-dual observe — the MERGED observation carries core
      // (Flutter) AND extensions.native (native) side by side.
      final ProcessResult observe =
          await Process.run(Platform.resolvedExecutable, <String>[
            'run',
            driveBin,
            'drive-dual',
            'observe',
            '--flutter-uri',
            flutterWs,
            '--native-uri',
            nativeEndpoint,
          ], workingDirectory: packageRoot);
      expect(observe.exitCode, 0, reason: 'observe stderr: ${observe.stderr}');
      final Map<String, dynamic> obsJson =
          (jsonDecode(observe.stdout as String) as Map).cast<String, dynamic>();
      final Map<String, dynamic> observation = (obsJson['observation'] as Map)
          .cast<String, dynamic>();
      expect(observation.containsKey('core'), isTrue);
      final Map<String, dynamic> exts = (observation['extensions'] as Map)
          .cast<String, dynamic>();
      expect(exts.containsKey('native'), isTrue, reason: 'exts: ${exts.keys}');

      // AC12: drive-dual invoke --tool native.tap — routed to the native
      // channel; a tool result comes back ({ok: ...}). STOP before SIGN IN.
      final ProcessResult invoke =
          await Process.run(Platform.resolvedExecutable, <String>[
            'run',
            driveBin,
            'drive-dual',
            'invoke',
            '--flutter-uri',
            flutterWs,
            '--native-uri',
            nativeEndpoint,
            '--tool',
            'native.tap',
            '--args',
            '{"label":"Email address"}',
          ], workingDirectory: packageRoot);
      // Routed successfully (exit 0); the tool itself may report ok:true|false
      // depending on whether the label is present — both are a routed result.
      expect(invoke.exitCode, 0, reason: 'invoke stderr: ${invoke.stderr}');
      final Map<String, dynamic> invokeJson =
          (jsonDecode(invoke.stdout as String) as Map).cast<String, dynamic>();
      expect(invokeJson['tool'], 'native.tap');
      expect(invokeJson['result'], isA<Map<String, dynamic>>());

      // Tear BOTH channels down via the single pid-file.
      final ProcessResult down = await Process.run(
        Platform.resolvedExecutable,
        <String>['run', driveBin, 'down', '--pid-file', pidFile],
        workingDirectory: packageRoot,
      );
      expect(down.exitCode, 0, reason: 'down stderr: ${down.stderr}');
      await up.exitCode.timeout(const Duration(seconds: 60));
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
