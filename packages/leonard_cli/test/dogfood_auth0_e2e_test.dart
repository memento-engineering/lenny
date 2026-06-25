/// Live, hardware-gated Auth0 round-trip dogfood e2e for `leonard_drive`
/// (m5, `lenny-qxx.5`) — the LAST functional milestone of the leonard_native
/// epic. It drives the full real Auth0 web login THROUGH THE LENNY HARNESS
/// (never raw Appium): boot a Flutter target AND the leonard_native host
/// against the SAME sim via m4's `up`, then drive the round-trip with stateless
/// `leonard_drive drive-dual invoke`/`observe` calls against the held dual
/// session, and assert the headline claim — after the OS-level Auth0 drive
/// completes, the deeplink callback returns control to the still-alive Flutter
/// process and the merged `core` fragment RELIGHTS with the authenticated
/// status (resume-on-Flutter), observed through the SAME merged observation m3
/// built, not via raw Appium `/source`.
///
/// The sequence (§3): observe → resolve the Flutter "Log in" node id (the
/// `core.tap` selector is `node_id`-only, so this is a TWO-CALL resolve) →
/// `core.tap` by id (opens the iOS ASWebAuthenticationSession sheet) →
/// `native.press consent_accept` → `native.enter_text` email (clear-before-type,
/// reads back exact) → `native.enter_text` password (reads back MASKED) →
/// `native.tap` Continue → an ADAPTIVE poll that clears the Auth0 authorize
/// screen (`native.tap` by label) + the iOS Save-Password alert
/// (`native.press alert_dismiss`) and watches the merged `core` fragment until
/// `logged in: <email>` appears.
///
/// The Flutter app process MUST stay alive the whole round-trip — the Auth0
/// sheet is presented ON TOP of the still-running `flutter run`-attached
/// process. There is NO terminate/activate anywhere (it would drop
/// `flutter_ws_uri` and break every `core.*` step + the resume-observe). Fresh
/// state comes from a single best-effort pre-`up` `xcrun simctl uninstall`.
///
/// Self-skips (one skipped test, no new tag — the house rule) when the live
/// tier is absent. The live tier needs ALL of `drive_dual_e2e_test.dart`'s env
/// PLUS the Auth0 credentials:
///
///   * a reachable Appium server (default `http://127.0.0.1:4723`, override via
///     `LEONARD_NATIVE_APPIUM_SERVER`);
///   * an already-booted iOS simulator udid in `LEONARD_NATIVE_SIM_UDID`;
///   * a built `Runner.app` path in `LEONARD_NATIVE_APP`;
///   * the Flutter project root in `LEONARD_NATIVE_FLUTTER_PROJECT`;
///   * a Flutter entrypoint in `LEONARD_NATIVE_FLUTTER_TARGET`;
///   * the Auth0 login email in `AUTH0_EMAIL`;
///   * the Auth0 password in `AUTH0_PASSWORD`.
///
/// CREDENTIALS VIA ENV ONLY — never hardcoded, never logged, never committed.
/// The test reads `AUTH0_EMAIL`/`AUTH0_PASSWORD` at start and passes them as
/// `--args` JSON to the `drive-dual invoke` subprocess; they are never written
/// to the trajectory/log. `AUTH0_PASSWORD` rides `--args` (visible in `ps`):
/// run only on trusted machines with a low-privilege throwaway account.
///
/// The env gate is synchronous at `main()`-time; Appium reachability is probed
/// asynchronously INSIDE the test body (a `sleep`-based sync probe would
/// deadlock the isolate and always self-skip — m4's rule, copied verbatim from
/// `drive_dual_e2e_test.dart`). The operator provisions Appium + the booted
/// sim; `up` boots neither (attach default).
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
const String _emailEnv = 'AUTH0_EMAIL';
const String _passwordEnv = 'AUTH0_PASSWORD';

const String _defaultServer = 'http://127.0.0.1:4723';

/// The bundle id of the lenny-instrumented auth0_sample target — uninstalled
/// pre-`up` for fresh state (NOT terminated; see the round-trip doc above).
const String _bundleId = 'com.nicospencer.lennyspike';

String _appiumServer() =>
    Platform.environment[_serverEnv]?.trim().isNotEmpty == true
    ? Platform.environment[_serverEnv]!.trim()
    : _defaultServer;

/// True when a live Appium server answers `GET /status` (W3C health check).
/// Async — the reachability probe runs INSIDE the test body. An HTTP round-trip
/// cannot be done from a synchronous main()-time gate: `sleep` blocks the
/// isolate's event loop, so the request would never complete (it would always
/// time out and the e2e would always self-skip, even with Appium running).
/// Copied verbatim from `drive_dual_e2e_test.dart`.
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
/// + the `.app` must exist + the Auth0 creds must be present. Appium
/// reachability is probed asynchronously inside the test body (see
/// [_appiumReachable]). The creds are checked for PRESENCE only here — their
/// values are never logged.
String? _envSkipReason() {
  final String? udid = Platform.environment[_udidEnv];
  final String? app = Platform.environment[_appEnv];
  final String? flutterProject = Platform.environment[_flutterProjectEnv];
  final String? flutterTarget = Platform.environment[_flutterTargetEnv];
  final String? email = Platform.environment[_emailEnv];
  final String? password = Platform.environment[_passwordEnv];
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
        'root + an entrypoint — live Auth0 dogfood e2e skipped';
  }
  if (email == null || email.isEmpty || password == null || password.isEmpty) {
    return '$_emailEnv + $_passwordEnv must be set (operator-supplied Auth0 '
        'credentials) — live Auth0 dogfood e2e skipped';
  }
  if (!File(app).existsSync() && !Directory(app).existsSync()) {
    return '$_appEnv ($app) does not exist — live Auth0 dogfood e2e skipped';
  }
  if (!File(p.join(flutterProject, 'pubspec.yaml')).existsSync()) {
    return '$_flutterProjectEnv ($flutterProject) is not a Flutter project '
        '(no pubspec.yaml) — live Auth0 dogfood e2e skipped';
  }
  return null;
}

/// Locate the native host runner relative to the cwd, mirroring
/// `drive_dual_e2e_test._hostScript()`'s dual-path resolver. Copied verbatim.
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

/// Run `leonard_drive drive-dual invoke` against the held dual session and
/// return the parsed `{tool, result}` JSON. `result` IS the canonical envelope
/// `{ok, value, error}` (`dispatch.dart`) — callers read `result['ok']`,
/// `result['value']['readback']`, etc., NEVER the flattened top level.
/// Drains BOTH stdout + stderr (full-pipe gotcha).
Future<Map<String, dynamic>> _invoke(
  String packageRoot,
  String driveBin,
  String flutterWs,
  String nativeEndpoint,
  String tool,
  String argsJson, {
  String? redact,
}) async {
  final ProcessResult r =
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
        tool,
        '--args',
        argsJson,
      ], workingDirectory: packageRoot);
  // Defense-in-depth (creds hygiene, §6): if a secret rode `--args`, scrub it
  // from stderr before it can reach a failure `reason` (in case drive-dual ever
  // echoes --args on a transport error). argsJson itself is never logged.
  String stderr = r.stderr as String;
  if (redact != null && redact.isNotEmpty) {
    stderr = stderr.replaceAll(redact, '***');
  }
  expect(r.exitCode, 0, reason: 'invoke $tool routed-fail stderr: $stderr');
  final Map<String, dynamic> j = (jsonDecode(r.stdout as String) as Map)
      .cast<String, dynamic>();
  return j;
}

/// Like [_invoke] but RETRIES until the tool returns `ok:true` (bounded). The
/// Auth0 web form renders ASYNCHRONOUSLY after consent — the proven spike slept
/// 7s here before touching the fields; a single shot races the page load and
/// gets "no element matched selector". Returns the last attempt (possibly
/// `ok:false`) so the caller's existing assertion reports a genuine failure.
Future<Map<String, dynamic>> _invokeUntilOk(
  String packageRoot,
  String driveBin,
  String flutterWs,
  String nativeEndpoint,
  String tool,
  String argsJson, {
  String? redact,
  int tries = 12,
  Duration gap = const Duration(seconds: 2),
}) async {
  Map<String, dynamic> j = <String, dynamic>{};
  for (int i = 0; i < tries; i++) {
    j = await _invoke(
      packageRoot,
      driveBin,
      flutterWs,
      nativeEndpoint,
      tool,
      argsJson,
      redact: redact,
    );
    final Map<String, dynamic> r = (j['result'] as Map).cast<String, dynamic>();
    if (r['ok'] == true) return j;
    await Future<void>.delayed(gap);
  }
  return j;
}

/// Run `leonard_drive drive-dual observe` and return the merged observation
/// (`{observation: <merged Observation.toJson()>}` → `observation`). Drains
/// both pipes.
Future<Map<String, dynamic>> _observe(
  String packageRoot,
  String driveBin,
  String flutterWs,
  String nativeEndpoint,
) async {
  final ProcessResult r =
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
  expect(r.exitCode, 0, reason: 'observe stderr: ${r.stderr}');
  final Map<String, dynamic> obsJson = (jsonDecode(r.stdout as String) as Map)
      .cast<String, dynamic>();
  return (obsJson['observation'] as Map).cast<String, dynamic>();
}

/// Walk the merged `core` fragment (a nested map/list) and find the integer
/// `id` of the first node whose `label == label`. Returns null on no match.
/// The Flutter semantics serialize each node as `{id, label, …}`
/// (`semantics_capture.dart`); the button is `Key('login_button')` with
/// `child: Text('Log in')`, so the semantics `label` surfaces `'Log in'`.
int? _findCoreNodeId(Object? core, String label) {
  if (core is Map) {
    if (core['label'] == label && core['id'] is int) {
      return core['id'] as int;
    }
    for (final Object? v in core.values) {
      final int? found = _findCoreNodeId(v, label);
      if (found != null) return found;
    }
  } else if (core is List) {
    for (final Object? e in core) {
      final int? found = _findCoreNodeId(e, label);
      if (found != null) return found;
    }
  }
  return null;
}

void main() {
  final String? envSkip = _envSkipReason();
  final String packageRoot = _findPackageRoot();
  final String driveBin = p.join(packageRoot, 'bin', 'leonard_drive.dart');

  test('lenny harness drives the full Auth0 round-trip + resumes on '
      'Flutter', () async {
    if (envSkip != null) {
      markTestSkipped(envSkip);
      return;
    }
    final String server = _appiumServer();
    if (!await _appiumReachable(server)) {
      markTestSkipped(
        'no Appium server at $server — live Auth0 dogfood e2e skipped',
      );
      return;
    }
    final String udid = Platform.environment[_udidEnv]!;
    final String app = Platform.environment[_appEnv]!;
    final String flutterProject = Platform.environment[_flutterProjectEnv]!;
    final String flutterTarget = Platform.environment[_flutterTargetEnv]!;
    // Creds: read here, passed only as --args JSON to the subprocess. NEVER
    // logged — `email` is used in an assertion substring; `password` never is.
    final String email = Platform.environment[_emailEnv]!;
    final String password = Platform.environment[_passwordEnv]!;
    final String nativeHost = _hostScript(packageRoot);

    // Step 0 (§3.0a): fresh-state prep BEFORE up — best-effort uninstall (NOT
    // terminate; terminate would drop the Flutter channel). Tolerate "not
    // installed".
    try {
      // Process.run buffers + drains both pipes; the exit code is intentionally
      // ignored — a not-installed app (or simctl absence) is fine here.
      await Process.run('xcrun', <String>[
        'simctl',
        'uninstall',
        udid,
        _bundleId,
      ]);
    } on Object {
      // Best-effort: simctl absence / not-installed must not fail the test.
    }

    final Directory tmp = Directory.systemTemp.createTempSync(
      'leonard_auth0_e2e',
    );
    final String pidFile = p.join(tmp.path, 'up.pid');
    final String uriFile = p.join(tmp.path, 'up.uris');
    final Completer<Map<String, dynamic>> ready =
        Completer<Map<String, dynamic>>();
    final Completer<void> shutdownSeen = Completer<void>();
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
      if (obj['event'] == 'shutdown' && !shutdownSeen.isCompleted) {
        shutdownSeen.complete();
      }
    });
    // Drain stderr (full-pipe gotcha) — buffer for triage on timeout.
    final List<String> err = <String>[];
    up.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(err.add);

    Map<String, dynamic>? lastObservation;
    try {
      final Map<String, dynamic> envelope = await ready.future.timeout(
        const Duration(seconds: 240),
        onTimeout: () => throw StateError(
          'no vm_service_ready line. up stdout:\n${out.join('\n')}',
        ),
      );
      final String flutterWs = envelope['flutter_ws_uri'] as String;
      final String nativeEndpoint = envelope['native_endpoint'] as String;
      expect(flutterWs, isNotEmpty);
      expect(nativeEndpoint, isNotEmpty);

      // ----- Step 1 (AC5): observe → resolve the Flutter "Log in" node id →
      // core.tap by node_id. core.tap is node_id-ONLY (§2.1) — a core.tap by
      // label would be schema-rejected.
      final Map<String, dynamic> obs0 = await _observe(
        packageRoot,
        driveBin,
        flutterWs,
        nativeEndpoint,
      );
      lastObservation = obs0;
      final int? loginId = _findCoreNodeId(obs0['core'], 'Log in');
      expect(
        loginId,
        isNotNull,
        reason:
            'no core node with label "Log in" in ${jsonEncode(obs0['core'])}',
      );
      final Map<String, dynamic> tapLogin = await _invoke(
        packageRoot,
        driveBin,
        flutterWs,
        nativeEndpoint,
        'core.tap',
        '{"node_id":$loginId}',
      );
      expect(tapLogin['tool'], 'core.tap');
      Map<String, dynamic> result = (tapLogin['result'] as Map)
          .cast<String, dynamic>();
      expect(
        result['ok'],
        isTrue,
        reason: 'core.tap failed: ${result['error']}',
      );

      // ----- Step 2 (AC6): accept the iOS consent sheet IF present. ADAPTIVE —
      // the fixture uses useEphemeralSession (forces a fresh session so the
      // login form ALWAYS shows; a persistent session would skip to the
      // authorize grant), and an ephemeral session presents NO consent sheet (no
      // shared data to approve). So a miss (ok:false / no alert open) is a
      // NON-FATAL no-op; when a sheet IS present it blocks the form, so accept
      // it. The email step (next) retries until the form renders regardless.
      await _invoke(
        packageRoot,
        driveBin,
        flutterWs,
        nativeEndpoint,
        'native.press',
        '{"key":"consent_accept"}',
      );

      // ----- Step 3 (AC7): clear+type email. Reads back EXACT, masked:false.
      // Retry-until-ok: the Auth0 form renders async after consent (§ the spike
      // slept here) — a single shot races the page load.
      final Map<String, dynamic> emailRes = await _invokeUntilOk(
        packageRoot,
        driveBin,
        flutterWs,
        nativeEndpoint,
        'native.enter_text',
        jsonEncode(<String, Object?>{
          'xpath': '//XCUIElementTypeTextField[@name="Email address"]',
          'text': email,
        }),
      );
      result = (emailRes['result'] as Map).cast<String, dynamic>();
      expect(
        result['ok'],
        isTrue,
        reason: 'email enter_text: ${result['error']}',
      );
      final Map<String, dynamic> emailValue = (result['value'] as Map)
          .cast<String, dynamic>();
      expect(emailValue['readback'], email);
      expect(emailValue['masked'], isFalse);

      // ----- Step 4 (AC8): clear+type password. Reads back MASKED — assert
      // masked:true + non-empty + readback != password. NEVER equality on a
      // secure field.
      final Map<String, dynamic> pwRes = await _invokeUntilOk(
        packageRoot,
        driveBin,
        flutterWs,
        nativeEndpoint,
        'native.enter_text',
        jsonEncode(<String, Object?>{
          'xpath': '//XCUIElementTypeSecureTextField[@name="Password"]',
          'text': password,
        }),
        redact: password,
      );
      result = (pwRes['result'] as Map).cast<String, dynamic>();
      expect(
        result['ok'],
        isTrue,
        reason: 'password enter_text: ${result['error']}',
      );
      final Map<String, dynamic> pwValue = (result['value'] as Map)
          .cast<String, dynamic>();
      expect(pwValue['masked'], isTrue);
      expect((pwValue['readback'] as String?) ?? '', isNotEmpty);
      // Inequality computed in Dart (NOT isNot(password)) so the secret literal
      // never lands in a matcher description / failure log (creds hygiene, §6).
      expect(
        (pwValue['readback'] as String?) != password,
        isTrue,
        reason: 'secure field read back the plaintext (masking failed)',
      );

      // ----- Step 5 (AC9): tap Continue (sign in). Retry-until-ok — the button
      // is on the same async-rendered form.
      final Map<String, dynamic> cont = await _invokeUntilOk(
        packageRoot,
        driveBin,
        flutterWs,
        nativeEndpoint,
        'native.tap',
        jsonEncode(<String, Object?>{
          'xpath': '//XCUIElementTypeButton[@name="Continue"]',
        }),
      );
      result = (cont['result'] as Map).cast<String, dynamic>();
      expect(result['ok'], isTrue, reason: 'Continue tap: ${result['error']}');

      // ----- Step 6a/6b + 7 (AC9/AC10/AC11): the adaptive poll. Each iteration:
      //   (a) try native.press alert_dismiss — the iOS Save-Password alert is
      //       ADAPTIVE; absent → ok:false is a NON-FATAL no-op.
      //   (b) once, try the Auth0 authorize screen by label (Accept/Allow/…).
      //   (c) observe → scan the merged core for `logged in: <email>` (resume)
      //       or `wrong email or password` (BAD_CREDS, a hard failure).
      // Bounded: 16 × 2s ≈ 32s, under @Timeout(300s).
      const List<String> authorizeLabels = <String>[
        'Accept',
        'Allow',
        'Authorize App',
        'Authorize',
      ];
      bool authorizeTried = false;
      String verdict = 'TIMEOUT';
      final String successNeedle = 'logged in: $email';
      Map<String, dynamic>? resumeObservation;
      for (int i = 0; i < 16; i++) {
        // (a) adaptive Save-Password dismiss — ok:false tolerated.
        await _invoke(
          packageRoot,
          driveBin,
          flutterWs,
          nativeEndpoint,
          'native.press',
          '{"key":"alert_dismiss"}',
        );

        // (b) adaptive Auth0 authorize — retried EACH poll until a button is
        // actually clicked (matching the spike's clicked_authorize latch); the
        // screen can lag the first poll on a first-consent run. A miss is a
        // no-op (the screen wasn't shown yet). Latches only on a real click.
        if (!authorizeTried) {
          for (final String label in authorizeLabels) {
            final Map<String, dynamic> auth = await _invoke(
              packageRoot,
              driveBin,
              flutterWs,
              nativeEndpoint,
              'native.tap',
              jsonEncode(<String, Object?>{'label': label}),
            );
            final Map<String, dynamic> r = (auth['result'] as Map)
                .cast<String, dynamic>();
            if (r['ok'] == true) {
              authorizeTried = true; // an authorize button was clicked.
              break;
            }
          }
        }

        // (c) observe → scan the merged core fragment.
        final Map<String, dynamic> obs = await _observe(
          packageRoot,
          driveBin,
          flutterWs,
          nativeEndpoint,
        );
        lastObservation = obs;
        final String coreJson = jsonEncode(obs['core']);
        if (coreJson.contains(successNeedle)) {
          verdict = 'LOGGED_IN';
          resumeObservation = obs;
          break;
        }
        if (jsonEncode(obs).contains('wrong email or password')) {
          verdict = 'BAD_CREDS';
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }

      expect(
        verdict,
        'LOGGED_IN',
        reason:
            'round-trip did not resume on Flutter (verdict=$verdict). up '
            'stderr:\n${err.join('\n')}\nlast core:\n'
            '${jsonEncode(lastObservation?['core'])}',
      );

      // AC10: the merged core fragment relit with the authenticated status.
      expect(jsonEncode(resumeObservation!['core']), contains(successNeedle));
      // AC11: the dual attach is still well-formed at resume (native attached).
      final Map<String, dynamic> exts = (resumeObservation['extensions'] as Map)
          .cast<String, dynamic>();
      expect(exts.containsKey('native'), isTrue, reason: 'exts: ${exts.keys}');

      // AC12: tear BOTH channels down via the single pid-file (m4 shutdown).
      final ProcessResult down = await Process.run(
        Platform.resolvedExecutable,
        <String>['run', driveBin, 'down', '--pid-file', pidFile],
        workingDirectory: packageRoot,
      );
      expect(down.exitCode, 0, reason: 'down stderr: ${down.stderr}');
      await up.exitCode.timeout(const Duration(seconds: 60));
      // AC12: `up` emitted {event:'shutdown'} on its way out (race-free via the
      // stdout listener completer, not a post-hoc scan of `out`).
      await shutdownSeen.future.timeout(const Duration(seconds: 10));
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
