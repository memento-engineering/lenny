/// Live, hardware-gated **Android** Auth0 round-trip dogfood e2e for
/// `leonard_drive` — the Android sibling of the iOS `dogfood_auth0_e2e_test`.
/// It drives the full real Auth0 web login THROUGH THE LENNY HARNESS (never raw
/// Appium): boot a Flutter target AND the leonard_native host against the SAME
/// emulator via `up` (with `--platform android`, which selects the
/// `UiAutomator2Backend`), then drive the round-trip with stateless
/// `leonard_drive drive-dual invoke`/`observe` calls, and assert the headline
/// claim — after the OS-level Auth0 drive completes, the deeplink callback
/// returns control to the still-alive Flutter process and the merged `core`
/// fragment RELIGHTS with the authenticated status (resume-on-Flutter).
///
/// ANDROID DIVERGENCES from the iOS file (all inside the backend or this test,
/// never in `leonard_agent` or the multi-host attach):
///   * the Auth0 handoff is a **Chrome Custom Tab**, not an
///     `ASWebAuthenticationSession` — there is NO system consent sheet, so the
///     iOS `native.press consent_accept` step is absent entirely;
///   * there is no SpringBoard "Save Password?" alert; Chrome may raise its own
///     save-password prompt, cleared adaptively by label tap in the poll;
///   * a masked Android field reads back EMPTY via `attribute/text` (Android
///     never exposes the secret), so the assertion is `masked == true` plus
///     readback-is-not-the-plaintext — NOT the iOS "non-empty bullets";
///   * fresh web state comes from `adb shell pm clear` on the app (and, when
///     `LEONARD_NATIVE_ANDROID_CLEAR_CHROME` is set, on Chrome, whose cookie
///     jar the Custom Tab shares) instead of `xcrun simctl uninstall`.
///
/// The Flutter app process MUST stay alive the whole round-trip. The
/// `UiAutomator2Backend` connects with `autoLaunch:false` and no app capability
/// precisely so Appium ATTACHES to the running `flutter run` process instead of
/// relaunching it — the Android form of iOS's no-terminate invariant.
///
/// Self-skips (one skipped test, no new tag — the house rule) when the live tier
/// is absent. The live tier needs ALL of:
///
///   * a reachable Appium server with the UiAutomator2 driver (default
///     `http://127.0.0.1:4723`, override via `LEONARD_NATIVE_APPIUM_SERVER`);
///   * an already-booted Android emulator id in `LEONARD_NATIVE_ANDROID_UDID`
///     (e.g. `emulator-5554`);
///   * a built `.apk` path in `LEONARD_NATIVE_ANDROID_APK`;
///   * the app package id in `LEONARD_NATIVE_ANDROID_PACKAGE`;
///   * the Flutter project root in `LEONARD_NATIVE_FLUTTER_PROJECT`;
///   * a Flutter entrypoint in `LEONARD_NATIVE_FLUTTER_TARGET`;
///   * the Auth0 credentials in `AUTH0_EMAIL` / `AUTH0_PASSWORD`.
///
/// The Auth0 form xpaths default to the Auth0 universal-login Android shape and
/// are overridable via `LEONARD_NATIVE_ANDROID_EMAIL_XPATH`,
/// `LEONARD_NATIVE_ANDROID_PW_XPATH`, `LEONARD_NATIVE_ANDROID_SUBMIT_XPATH`, so
/// a tenant with a different template retunes without editing this file.
///
/// CREDENTIALS VIA ENV ONLY — never hardcoded, never logged, never committed.
/// `AUTH0_PASSWORD` rides `--args` (visible in `ps`): run only on trusted
/// machines with a low-privilege throwaway account.
@Timeout(Duration(seconds: 300))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _serverEnv = 'LEONARD_NATIVE_APPIUM_SERVER';
const String _udidEnv = 'LEONARD_NATIVE_ANDROID_UDID';
const String _apkEnv = 'LEONARD_NATIVE_ANDROID_APK';
const String _packageEnv = 'LEONARD_NATIVE_ANDROID_PACKAGE';
const String _flutterProjectEnv = 'LEONARD_NATIVE_FLUTTER_PROJECT';
const String _flutterTargetEnv = 'LEONARD_NATIVE_FLUTTER_TARGET';
const String _emailEnv = 'AUTH0_EMAIL';
const String _passwordEnv = 'AUTH0_PASSWORD';
const String _clearChromeEnv = 'LEONARD_NATIVE_ANDROID_CLEAR_CHROME';

const String _defaultServer = 'http://127.0.0.1:4723';

/// Auth0 universal-login on Android renders in a Chrome Custom Tab; the web
/// inputs surface in the UiAutomator2 tree as `android.widget.EditText`.
const String _defaultEmailXpath =
    '//android.widget.EditText[@resource-id="username"]';
const String _defaultPwXpath =
    '//android.widget.EditText[@resource-id="password"]';
const String _defaultSubmitXpath = '//android.widget.Button[@text="Continue"]';

String _env(String key, String fallback) =>
    Platform.environment[key]?.trim().isNotEmpty == true
    ? Platform.environment[key]!.trim()
    : fallback;

String _appiumServer() => _env(_serverEnv, _defaultServer);

/// True when a live Appium server answers `GET /status` (W3C health check).
/// Async — the probe runs INSIDE the test body. A sync `sleep`-based probe
/// would block the isolate's event loop and always self-skip. Copied verbatim
/// from `dogfood_auth0_e2e_test.dart`.
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

/// Env-only skip reason (synchronous). Credentials are checked for PRESENCE
/// only — their values are never logged.
String? _envSkipReason() {
  final String? udid = Platform.environment[_udidEnv];
  final String? apk = Platform.environment[_apkEnv];
  final String? pkg = Platform.environment[_packageEnv];
  final String? flutterProject = Platform.environment[_flutterProjectEnv];
  final String? flutterTarget = Platform.environment[_flutterTargetEnv];
  final String? email = Platform.environment[_emailEnv];
  final String? password = Platform.environment[_passwordEnv];
  if (udid == null ||
      udid.isEmpty ||
      apk == null ||
      apk.isEmpty ||
      pkg == null ||
      pkg.isEmpty ||
      flutterProject == null ||
      flutterProject.isEmpty ||
      flutterTarget == null ||
      flutterTarget.isEmpty) {
    return '$_udidEnv + $_apkEnv + $_packageEnv + $_flutterProjectEnv + '
        '$_flutterTargetEnv must point at a booted Android emulator + a built '
        '.apk + its package id + a Flutter project root + an entrypoint — '
        'live Android Auth0 dogfood e2e skipped';
  }
  if (email == null || email.isEmpty || password == null || password.isEmpty) {
    return '$_emailEnv + $_passwordEnv must be set (operator-supplied Auth0 '
        'credentials) — live Android Auth0 dogfood e2e skipped';
  }
  if (!File(apk).existsSync()) {
    return '$_apkEnv ($apk) does not exist — live Android Auth0 dogfood e2e '
        'skipped';
  }
  if (!File(p.join(flutterProject, 'pubspec.yaml')).existsSync()) {
    return '$_flutterProjectEnv ($flutterProject) is not a Flutter project '
        '(no pubspec.yaml) — live Android Auth0 dogfood e2e skipped';
  }
  return null;
}

/// Locate the native host runner relative to the cwd. Copied verbatim from
/// `dogfood_auth0_e2e_test.dart`.
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

/// Run `drive-dual invoke` and return the parsed `{tool, result}` JSON.
/// `result` IS the canonical `{ok, value, error}` envelope. Drains both pipes.
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
  String stderr = r.stderr as String;
  if (redact != null && redact.isNotEmpty) {
    stderr = stderr.replaceAll(redact, '***');
  }
  expect(r.exitCode, 0, reason: 'invoke $tool routed-fail stderr: $stderr');
  return (jsonDecode(r.stdout as String) as Map).cast<String, dynamic>();
}

/// Like [_invoke] but RETRIES until the tool returns `ok:true` (bounded). The
/// Auth0 form renders ASYNCHRONOUSLY inside the Custom Tab; a single shot races
/// the page load. Returns the last attempt so the caller's assertion reports a
/// genuine failure.
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

/// Run `drive-dual observe` and return the merged observation.
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

/// Walk the merged `core` fragment and find the integer `id` of the first node
/// whose `label == label`. Copied verbatim from `dogfood_auth0_e2e_test.dart`.
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

void main() {
  final String? envSkip = _envSkipReason();
  final String packageRoot = _findPackageRoot();
  final String driveBin = p.join(packageRoot, 'bin', 'leonard_drive.dart');

  test('lenny harness drives the full Android Auth0 round-trip + resumes on '
      'Flutter', () async {
    if (envSkip != null) {
      markTestSkipped(envSkip);
      return;
    }
    final String server = _appiumServer();
    if (!await _appiumReachable(server)) {
      markTestSkipped(
        'no Appium server at $server — live Android Auth0 dogfood e2e skipped',
      );
      return;
    }
    final String udid = Platform.environment[_udidEnv]!;
    final String apk = Platform.environment[_apkEnv]!;
    final String pkg = Platform.environment[_packageEnv]!;
    final String flutterProject = Platform.environment[_flutterProjectEnv]!;
    final String flutterTarget = Platform.environment[_flutterTargetEnv]!;
    final String email = Platform.environment[_emailEnv]!;
    final String password = Platform.environment[_passwordEnv]!;
    final String emailXpath = _env(
      'LEONARD_NATIVE_ANDROID_EMAIL_XPATH',
      _defaultEmailXpath,
    );
    final String pwXpath = _env(
      'LEONARD_NATIVE_ANDROID_PW_XPATH',
      _defaultPwXpath,
    );
    final String submitXpath = _env(
      'LEONARD_NATIVE_ANDROID_SUBMIT_XPATH',
      _defaultSubmitXpath,
    );
    final String nativeHost = _hostScript(packageRoot);

    // Step 0: fresh-state prep BEFORE up — best-effort `pm clear` (NOT a
    // force-stop of a running app; `up` has not started it yet). Clearing the
    // app drops its Auth0 credential store; clearing Chrome (opt-in) drops the
    // Custom Tab's shared cookie jar, which is what makes the login form render
    // instead of skipping straight to the authorize grant.
    for (final String target in <String>[
      pkg,
      if (Platform.environment[_clearChromeEnv]?.isNotEmpty == true)
        'com.android.chrome',
    ]) {
      try {
        await Process.run('adb', <String>[
          '-s',
          udid,
          'shell',
          'pm',
          'clear',
          target,
        ]);
      } on Object {
        // Best-effort: adb absence / not-installed must not fail the test.
      }
    }

    final Directory tmp = Directory.systemTemp.createTempSync(
      'leonard_auth0_android_e2e',
    );
    final String pidFile = p.join(tmp.path, 'up.pid');
    final String uriFile = p.join(tmp.path, 'up.uris');
    final Completer<Map<String, dynamic>> ready =
        Completer<Map<String, dynamic>>();
    final Completer<void> shutdownSeen = Completer<void>();
    final List<String> out = <String>[];

    // `up` with --platform android: launchDualTarget forwards it to the native
    // host, whose backendForPlatform selects the UiAutomator2Backend. One
    // --udid (the emulator id) drives BOTH `flutter run -d` and the host.
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
          apk,
          '--platform',
          'android',
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

      // ----- Step 1: observe → resolve the Flutter "Log in" node id →
      // core.tap by node_id (core.tap is node_id-ONLY).
      final Map<String, dynamic> obs0 = await _observe(
        packageRoot,
        driveBin,
        flutterWs,
        nativeEndpoint,
      );
      lastObservation = obs0;
      // The native fragment must be present — the UiAutomator2 host attached.
      expect(
        (obs0['extensions'] as Map).containsKey('native'),
        isTrue,
        reason: 'native fragment absent: ${jsonEncode(obs0['extensions'])}',
      );
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
      expect(result['ok'], isTrue, reason: 'core.tap failed: $result');

      // ----- Step 2: NO consent step. Android opens a Chrome Custom Tab with
      // no system consent sheet (the iOS ASWebAuthenticationSession alert has
      // no Android counterpart). The email step below retries until the web
      // form renders inside the tab.

      // ----- Step 3: clear+type email. Reads back EXACT, masked:false.
      final Map<String, dynamic> emailRes = await _invokeUntilOk(
        packageRoot,
        driveBin,
        flutterWs,
        nativeEndpoint,
        'native.enter_text',
        jsonEncode(<String, Object?>{'xpath': emailXpath, 'text': email}),
      );
      result = (emailRes['result'] as Map).cast<String, dynamic>();
      expect(
        result['ok'],
        isTrue,
        reason: 'email enter_text ($emailXpath): ${result['error']}',
      );
      final Map<String, dynamic> emailValue = (result['value'] as Map)
          .cast<String, dynamic>();
      expect(emailValue['readback'], email);
      expect(emailValue['masked'], isFalse);

      // The native fragment must reflect the typed email after the
      // refresh-after-act — the Android parser maps an EditText's `text` to the
      // node `value`, so the observation carries it.
      final Map<String, dynamic> afterEmail = await _observe(
        packageRoot,
        driveBin,
        flutterWs,
        nativeEndpoint,
      );
      lastObservation = afterEmail;
      expect(
        jsonEncode(afterEmail['extensions']).contains(email),
        isTrue,
        reason: 'typed email never reached the native observation fragment',
      );

      // ----- Step 4: clear+type password. ANDROID DIVERGENCE: a masked field
      // reads back EMPTY via attribute/text (Android never exposes the secret),
      // so assert masked:true + readback != plaintext, and NOT the iOS
      // "non-empty bullets" clause.
      final Map<String, dynamic> pwRes = await _invokeUntilOk(
        packageRoot,
        driveBin,
        flutterWs,
        nativeEndpoint,
        'native.enter_text',
        jsonEncode(<String, Object?>{'xpath': pwXpath, 'text': password}),
        redact: password,
      );
      result = (pwRes['result'] as Map).cast<String, dynamic>();
      expect(
        result['ok'],
        isTrue,
        reason: 'password enter_text ($pwXpath): ${result['error']}',
      );
      final Map<String, dynamic> pwValue = (result['value'] as Map)
          .cast<String, dynamic>();
      expect(pwValue['masked'], isTrue);
      // Inequality computed in Dart (NOT isNot(password)) so the secret never
      // lands in a matcher description / failure log.
      expect(
        (pwValue['readback'] as String?) != password,
        isTrue,
        reason: 'secure field read back the plaintext (masking failed)',
      );

      // ----- Step 5: submit the form (sign in). Retry-until-ok.
      final Map<String, dynamic> cont = await _invokeUntilOk(
        packageRoot,
        driveBin,
        flutterWs,
        nativeEndpoint,
        'native.tap',
        jsonEncode(<String, Object?>{'xpath': submitXpath}),
      );
      result = (cont['result'] as Map).cast<String, dynamic>();
      expect(
        result['ok'],
        isTrue,
        reason: 'submit tap ($submitXpath): ${result['error']}',
      );

      // ----- Steps 6+7: the adaptive poll. Each iteration:
      //   (a) clear Chrome's own save-password prompt by label (Android's
      //       counterpart to the iOS SpringBoard alert — a real widget in
      //       /source, so a label tap, NOT press('alert_dismiss') which is
      //       iOS-only and would throw);
      //   (b) once, clear the Auth0 authorize screen by label;
      //   (c) observe → scan the merged core for `logged in: <email>` (resume)
      //       or `wrong email or password` (BAD_CREDS, a hard failure).
      // Bounded: 16 × 2s ≈ 32s, under @Timeout(300s).
      const List<String> dismissLabels = <String>[
        'Never',
        'No thanks',
        'Not now',
      ];
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
        for (final String label in dismissLabels) {
          await _invoke(
            packageRoot,
            driveBin,
            flutterWs,
            nativeEndpoint,
            'native.tap',
            jsonEncode(<String, Object?>{'label': label}),
          );
        }
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
              authorizeTried = true;
              break;
            }
          }
        }
        final Map<String, dynamic> obs = await _observe(
          packageRoot,
          driveBin,
          flutterWs,
          nativeEndpoint,
        );
        lastObservation = obs;
        if (jsonEncode(obs['core']).contains(successNeedle)) {
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
            'Android round-trip did not resume on Flutter (verdict=$verdict). '
            'up stderr:\n${err.join('\n')}\nlast core:\n'
            '${jsonEncode(lastObservation?['core'])}',
      );

      // The merged core fragment relit with the authenticated status.
      expect(jsonEncode(resumeObservation!['core']), contains(successNeedle));
      // The dual attach is still well-formed at resume (native still attached).
      final Map<String, dynamic> exts = (resumeObservation['extensions'] as Map)
          .cast<String, dynamic>();
      expect(exts.containsKey('native'), isTrue, reason: 'exts: ${exts.keys}');

      // Tear BOTH channels down via the single pid-file.
      final ProcessResult down = await Process.run(
        Platform.resolvedExecutable,
        <String>['run', driveBin, 'down', '--pid-file', pidFile],
        workingDirectory: packageRoot,
      );
      expect(down.exitCode, 0, reason: 'down stderr: ${down.stderr}');
      await up.exitCode.timeout(const Duration(seconds: 60));
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
