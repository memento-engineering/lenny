/// Live end-to-end proof of target-agnostic native driving: a real iOS
/// simulator driven through a real Appium server, served over the VM service by
/// `ExplorationHost` (no Flutter) and driven by a `LeonardSession` exactly as
/// `leonard_cli` / `leonard_drive` would — the native analogue of
/// `leonard_tmux/test/host_e2e_test.dart`.
///
/// This is the ONLY tier that proves `AppiumBackend`'s real W3C wiring: the
/// `POST /alert/accept` consent path, the masked secure-field readback, and the
/// per-platform keyboard dismiss inside `AppiumBackend.enterText`.
///
/// Self-skips (one skipped test, no new tag — mirroring the tmux/dogfood
/// precedents) when the live tier is absent. The live tier needs ALL of:
///
///   * a reachable Appium server (default `http://127.0.0.1:4723`, override via
///     `LEONARD_NATIVE_APPIUM_SERVER`);
///   * an already-booted iOS simulator udid in `LEONARD_NATIVE_SIM_UDID`;
///   * a built `Runner.app` path in `LEONARD_NATIVE_APP`.
///
/// The operator provisions Appium + the booted sim; this host boots neither
/// (m4 owns that lifecycle). The drive STOPS before SIGN IN (m5 owns the Auth0
/// round-trip): it proves host-boots-and-drives + masked-password readback,
/// NOT authentication.
@Timeout(Duration(seconds: 240))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

const String _serverEnv = 'LEONARD_NATIVE_APPIUM_SERVER';
const String _udidEnv = 'LEONARD_NATIVE_SIM_UDID';
const String _appEnv = 'LEONARD_NATIVE_APP';

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
      // Drain so the socket can close cleanly.
      await res.drain<void>(null);
      return res.statusCode >= 200 && res.statusCode < 500;
    } finally {
      client.close(force: true);
    }
  } on Object {
    return false;
  }
}

/// Env-only skip reason (synchronous): the udid/app must be set + the `.app`
/// must exist. Appium reachability is probed asynchronously inside the test
/// body (see [_appiumReachable]).
String? _envSkipReason() {
  final String? udid = Platform.environment[_udidEnv];
  final String? app = Platform.environment[_appEnv];
  if (udid == null || udid.isEmpty || app == null || app.isEmpty) {
    return '$_udidEnv + $_appEnv must point at a booted iOS sim + a built '
        '.app — live native driving e2e skipped';
  }
  if (!File(app).existsSync() && !Directory(app).existsSync()) {
    return '$_appEnv ($app) does not exist — live native driving e2e skipped';
  }
  return null;
}

/// Locate the host runner relative to the current working directory, which
/// differs by invocation: `dart test packages/leonard_native` runs from the
/// repo root; `melos exec` runs from the package directory.
String _hostScript() {
  const List<String> candidates = <String>[
    'bin/leonard_native_host.dart',
    'packages/leonard_native/bin/leonard_native_host.dart',
  ];
  for (final String p in candidates) {
    if (File(p).existsSync()) return p;
  }
  throw StateError(
    'cannot locate leonard_native_host.dart from ${Directory.current.path}',
  );
}

void main() {
  final String? envSkip = _envSkipReason();

  test('drives a live native iOS host over the VM service end-to-end', () async {
    if (envSkip != null) {
      markTestSkipped(envSkip);
      return;
    }
    final String server = _appiumServer();
    if (!await _appiumReachable(server)) {
      markTestSkipped(
        'no Appium server at $server — live native driving e2e skipped',
      );
      return;
    }
    final String udid = Platform.environment[_udidEnv]!;
    final String app = Platform.environment[_appEnv]!;

    // A per-run nonce email so the readback assertion can't pass on stale text.
    final String email =
        'lenny+${DateTime.now().millisecondsSinceEpoch}'
        '@example.com';
    const String password = 'Sup3rSecret!pw';

    final List<String> lines = <String>[];
    final Completer<Uri> serviceUri = Completer<Uri>();
    final Completer<void> ready = Completer<void>();
    final RegExp uriRe = RegExp(r'(http://(?:127\.0\.0\.1|\[::1\]):\d+/\S*)');

    void scan(String line) {
      lines.add(line);
      final RegExpMatch? m = uriRe.firstMatch(line);
      if (m != null && !serviceUri.isCompleted) {
        serviceUri.complete(Uri.parse(m.group(1)!));
      }
      if (line.contains('LEONARD_HOST_READY') && !ready.isCompleted) {
        ready.complete();
      }
    }

    final Process proc = await Process.start('dart', <String>[
      'run',
      '--enable-vm-service=0',
      '--disable-service-auth-codes',
      _hostScript(),
      '--server',
      server,
      '--udid',
      udid,
      '--app',
      app,
      '--platform',
      'ios',
    ]);
    proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(scan);
    proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(scan);

    LeonardSession? session;
    try {
      final Uri httpUri = await serviceUri.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () => throw StateError(
          'no VM service URI from host. child output:\n${lines.join('\n')}',
        ),
      );
      await ready.future.timeout(
        const Duration(seconds: 120),
        onTimeout: () => throw StateError(
          'host never reported ready. child output:\n${lines.join('\n')}',
        ),
      );

      // http://host:port/<token?>/  ->  ws://host:port/<token?>/ws
      final Uri wsUri = httpUri.replace(
        scheme: 'ws',
        pathSegments: <String>[
          ...httpUri.pathSegments.where((String s) => s.isNotEmpty),
          'ws',
        ],
      );

      session = await LeonardSession.connect(wsUri);
      await session.start('native auth0 drive', const LeonardConfig());

      // The native fragment must be present once the watcher has seeded.
      final Observation first = await session.observe();
      expect(
        first.extensions.containsKey('native'),
        isTrue,
        reason: 'native fragment absent from first observation',
      );

      // 1) Tap the host "Log in" button (launches ASWebAuthenticationSession).
      final Map<String, dynamic> loggedIn = await session.act(<String, dynamic>{
        'name': 'native.tap',
        'args': <String, dynamic>{'label': 'Log in'},
      });
      expect(loggedIn['ok'], isTrue, reason: 'tap Log in: $loggedIn');

      // 2) Accept the SpringBoard consent popup via the W3C alert/accept path.
      //    (The consent dialog is a SEPARATE process — NOT in /source — so this
      //    is the alert endpoint, not an xpath find.)
      final Map<String, dynamic> consent = await session.act(<String, dynamic>{
        'name': 'native.press',
        'args': <String, dynamic>{'key': 'consent_accept'},
      });
      expect(consent['ok'], isTrue, reason: 'consent_accept: $consent');

      // 3) Type the email into the Auth0 "Email address" field. The XPath tier
      //    is load-bearing for the (possibly anonymous) web form field.
      final Map<String, dynamic> typedEmail = await session.act(
        <String, dynamic>{
          'name': 'native.enter_text',
          'args': <String, dynamic>{
            'xpath': "//XCUIElementTypeTextField[@name='Email address']",
            'text': email,
          },
        },
      );
      expect(typedEmail['ok'], isTrue, reason: 'enter_text email: $typedEmail');
      final Map<String, dynamic> emailVal = (typedEmail['value'] as Map)
          .cast<String, dynamic>();
      expect(
        emailVal['readback'],
        email,
        reason: 'email readback should equal the typed nonce',
      );
      expect(
        emailVal['masked'],
        isFalse,
        reason: 'a normal TextField must not be masked',
      );

      // The native fragment should reflect the typed email after the
      // refresh-after-act.
      final Observation afterEmail = await session.observe();
      expect(afterEmail.extensions.containsKey('native'), isTrue);
      expect(
        jsonEncode(afterEmail.toJson()).contains(email),
        isTrue,
        reason: 'typed email never reached the native observation fragment',
      );

      // 4) Type the password into the SecureTextField. It reads back masked
      //    (non-empty bullets, != plaintext); `masked` is element-type-derived.
      final Map<String, dynamic> typedPw = await session.act(<String, dynamic>{
        'name': 'native.enter_text',
        'args': <String, dynamic>{
          'xpath': "//XCUIElementTypeSecureTextField[@name='Password']",
          'text': password,
        },
      });
      expect(typedPw['ok'], isTrue, reason: 'enter_text password: $typedPw');
      final Map<String, dynamic> pwVal = (typedPw['value'] as Map)
          .cast<String, dynamic>();
      expect(
        pwVal['masked'],
        isTrue,
        reason: 'a SecureTextField must report masked:true',
      );
      final Object? readback = pwVal['readback'];
      expect(
        readback,
        isA<String>().having(
          (String s) => s.isNotEmpty,
          'non-empty masked readback',
          isTrue,
        ),
        reason: 'masked readback must be non-empty bullets',
      );
      expect(
        readback,
        isNot(password),
        reason: 'masked readback must NOT equal the plaintext password',
      );

      // STOP before SIGN IN — m5 owns sign-in / callback / resume-on-Flutter.
    } finally {
      await session?.end();
      proc.kill(ProcessSignal.sigterm);
      await proc.exitCode.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          proc.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    }
  });
}
