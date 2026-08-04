/// UNIT (NOT e2e): exercises the REAL [XcuiTestBackend] over a MOCKED
/// `http.Client` (no Appium server, no device). Locks the FN3 masked-flag
/// wiring (AC9/AC18) — that `enter_text` derives `masked` from the element
/// TYPE via `attribute/type`, NOT the tag-name `/name` route (which on
/// appium-xcuitest returns the accessibility name, e.g. "Password", and would
/// make masked always false on the live Auth0 drive). This is the exact bug
/// the fake-backed extension tests structurally cannot catch.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:leonard_native/leonard_native.dart';
import 'package:test/test.dart';

void main() {
  group('XcuiTestBackend.connect capabilities', () {
    test('merges safe extras into the complete session request', () async {
      http.Request? sessionRequest;
      final MockClient client = MockClient((http.Request request) async {
        if (request.url.path == '/session') {
          sessionRequest = request;
          return http.Response(
            jsonEncode(<String, Object?>{
              'value': <String, Object?>{'sessionId': 'ios-session'},
            }),
            200,
          );
        }
        return http.Response(jsonEncode(<String, Object?>{'value': null}), 200);
      });
      final XcuiTestBackend backend = XcuiTestBackend(
        udid: 'iphone',
        app: '/x/Runner.app',
        client: client,
      );

      await backend.connect(
        extraCapabilities: <String, Object?>{
          'appium:autoAcceptAlerts': true,
          'appium:wdaLaunchTimeout': 240000,
          'appium:forceSimulatorSoftwareKeyboardPresence': false,
        },
      );

      expect(sessionRequest?.method, 'POST');
      final Map<String, Object?> body =
          jsonDecode(sessionRequest!.body) as Map<String, Object?>;
      final Map<String, Object?> capabilities =
          body['capabilities']! as Map<String, Object?>;
      expect(capabilities['alwaysMatch'], <String, Object?>{
        'platformName': 'iOS',
        'appium:automationName': 'XCUITest',
        'appium:udid': 'iphone',
        'appium:app': '/x/Runner.app',
        'appium:forceSimulatorSoftwareKeyboardPresence': false,
        'appium:noReset': true,
        'appium:autoAcceptAlerts': true,
        'appium:wdaLaunchTimeout': 240000,
      });
      expect(capabilities['firstMatch'], <Object?>[<String, Object?>{}]);
    });

    const List<String> deniedKeys = <String>[
      'appium:app',
      'appium:appPackage',
      'appium:appActivity',
      'appium:autoLaunch',
      'appium:noReset',
      'appium:fullReset',
      'app',
      'appPackage',
      'appActivity',
      'autoLaunch',
      'noReset',
      'fullReset',
    ];
    for (final String key in deniedKeys) {
      test('rejects $key before transport I/O', () async {
        int requests = 0;
        final XcuiTestBackend backend = XcuiTestBackend(
          udid: 'iphone',
          app: '/x/Runner.app',
          client: MockClient((http.Request request) async {
            requests++;
            return http.Response('{}', 200);
          }),
        );

        await expectLater(
          backend.connect(extraCapabilities: <String, Object?>{key: true}),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError error) => error.message.toString(),
              'message',
              contains(key),
            ),
          ),
        );
        expect(requests, 0);
      });
    }
  });

  test('platform is fixed to ios', () async {
    final XcuiTestBackend b = XcuiTestBackend(udid: 'U', app: '/x/Runner.app');
    expect(b.platform, 'ios');
    await b.close();
  });

  test('enter posts a newline keystroke without dismissing keyboard', () async {
    final List<String> hits = <String>[];
    http.Request? keysRequest;
    final MockClient client = MockClient((http.Request req) async {
      hits.add('${req.method} ${req.url.path}');
      if (req.url.path == '/session') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'value': <String, Object?>{'sessionId': 's1'},
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      if (req.url.path == '/session/s1/keys') keysRequest = req;
      return http.Response(
        jsonEncode(<String, Object?>{'value': null}),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final XcuiTestBackend b = XcuiTestBackend(
      udid: 'U',
      app: '/x/Runner.app',
      osVersion: '17',
      client: client,
    );

    await b.connect();
    await b.press('enter');

    expect(hits, contains('POST /session/s1/keys'));
    expect(jsonDecode(keysRequest!.body), <String, Object?>{
      'value': <String>['\n'],
    });
    expect(hits, isNot(contains('POST /session/s1/element')));
    await b.close();
  });

  group('XcuiTestBackend.enterText masked flag (element-type-derived)', () {
    late List<String> hits;

    // A backend wired to a MockClient that reports the given element `type`.
    XcuiTestBackend backendReporting(String elementType) {
      hits = <String>[];
      final MockClient client = MockClient((http.Request req) async {
        final String path = req.url.path;
        hits.add('${req.method} $path');
        Object? value;
        if (req.method == 'POST' && path == '/session') {
          value = <String, Object?>{'sessionId': 's1'};
        } else if (path.endsWith('/attribute/type')) {
          value = elementType;
        } else if (path.endsWith('/attribute/value')) {
          value = elementType == 'XCUIElementTypeSecureTextField'
              ? '••••••' // masked bullets
              : 'hello@example.com';
        } else {
          value = null; // context / clear / value / anything else -> 200 ok
        }
        return http.Response(
          jsonEncode(<String, Object?>{'value': value}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      return XcuiTestBackend(udid: 'U', app: '/x/Runner.app', client: client);
    }

    test(
      'SecureTextField -> masked:true, reads attribute/type (not /name)',
      () async {
        final XcuiTestBackend b = backendReporting(
          'XCUIElementTypeSecureTextField',
        );
        await b.connect();
        final ({String readback, bool masked}) r = await b.enterText(
          const NativeTarget(elementId: 'E', via: 'xpath'),
          'sup3r-secret',
        );
        expect(r.masked, isTrue);
        expect(r.readback, isNotEmpty);
        expect(r.readback, isNot('sup3r-secret')); // masked, not plaintext
        // It MUST consult the element TYPE, and MUST NOT use the tag-name route.
        expect(hits, contains('GET /session/s1/element/E/attribute/type'));
        expect(hits, isNot(contains('GET /session/s1/element/E/name')));
        await b.close();
      },
    );

    test(
      'plain TextField -> masked:false, readback is the typed value',
      () async {
        final XcuiTestBackend b = backendReporting('XCUIElementTypeTextField');
        await b.connect();
        final ({String readback, bool masked}) r = await b.enterText(
          const NativeTarget(elementId: 'E', via: 'xpath'),
          'hello@example.com',
        );
        expect(r.masked, isFalse);
        expect(r.readback, 'hello@example.com');
        expect(hits, contains('GET /session/s1/element/E/attribute/value'));
        expect(
          hits,
          isNot(contains('GET /session/s1/element/E/attribute/text')),
        );
        expect(hits, isNot(contains('POST /session/s1/back')));
        await b.close();
      },
    );
  });

  // AC1 (m5): `press('alert_dismiss')` posts to /session/<sid>/alert/dismiss
  // with an empty body (parallel to consent_accept -> /alert/accept); a W3C
  // "no alert open" error envelope surfaces as a NativeException (so the tool
  // returns ok:false), NOT a crash.
  group(
    'XcuiTestBackend.press alert endpoints (consent_accept/alert_dismiss)',
    () {
      late List<String> hits;

      // A backend whose alert endpoints are present iff [alertOpen]; when no
      // alert is open the alert/accept|dismiss endpoints return the W3C
      // "no alert open" error envelope (HTTP 404 + value.error).
      XcuiTestBackend backend({required bool alertOpen}) {
        hits = <String>[];
        final MockClient client = MockClient((http.Request req) async {
          final String path = req.url.path;
          hits.add('${req.method} $path');
          if (req.method == 'POST' && path == '/session') {
            return http.Response(
              jsonEncode(<String, Object?>{
                'value': <String, Object?>{'sessionId': 's1'},
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json',
              },
            );
          }
          if (!alertOpen &&
              (path.endsWith('/alert/accept') ||
                  path.endsWith('/alert/dismiss'))) {
            // W3C "no such alert" — value.error present, non-2xx status.
            return http.Response(
              jsonEncode(<String, Object?>{
                'value': <String, Object?>{
                  'error': 'no such alert',
                  'message': 'no alert open',
                },
              }),
              404,
              headers: const <String, String>{
                'content-type': 'application/json',
              },
            );
          }
          return http.Response(
            jsonEncode(<String, Object?>{'value': null}),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        });
        return XcuiTestBackend(udid: 'U', app: '/x/Runner.app', client: client);
      }

      test(
        'alert_dismiss -> POST /session/<sid>/alert/dismiss, empty body',
        () async {
          final XcuiTestBackend b = backend(alertOpen: true);
          await b.connect();
          await b.press('alert_dismiss');
          expect(hits, contains('POST /session/s1/alert/dismiss'));
          await b.close();
        },
      );

      test(
        'alert_dismiss with no alert open -> NativeException (not a crash)',
        () async {
          final XcuiTestBackend b = backend(alertOpen: false);
          await b.connect();
          await expectLater(
            () => b.press('alert_dismiss'),
            throwsA(isA<NativeException>()),
          );
          // It still issued the request (so the no-op surfaces as ok:false at the
          // tool layer), and did not crash with a FormatException.
          expect(hits, contains('POST /session/s1/alert/dismiss'));
          await b.close();
        },
      );

      test(
        'consent_accept -> POST /session/<sid>/alert/accept (parity)',
        () async {
          final XcuiTestBackend b = backend(alertOpen: true);
          await b.connect();
          await b.press('consent_accept');
          expect(hits, contains('POST /session/s1/alert/accept'));
          await b.close();
        },
      );

      test('back is rejected as an unknown iOS press key', () async {
        final XcuiTestBackend b = backend(alertOpen: true);
        await b.connect();
        await expectLater(
          () => b.press('back'),
          throwsA(isA<NativeException>()),
        );
        expect(hits, isNot(contains('POST /session/s1/back')));
        await b.close();
      });

      test('dismiss_overlay is rejected without performing I/O', () async {
        final XcuiTestBackend b = backend(alertOpen: true);
        await b.connect();
        final List<String> before = List<String>.of(hits);
        await expectLater(
          () => b.press('dismiss_overlay'),
          throwsA(
            isA<NativeException>().having(
              (NativeException e) => e.message,
              'message',
              'unknown press key: dismiss_overlay',
            ),
          ),
        );
        expect(hits, before);
        expect(
          hits.where(
            (String hit) =>
                hit.contains('/alert/') ||
                hit.contains('/back') ||
                hit.contains('/source') ||
                hit.contains('/element'),
          ),
          isEmpty,
        );
        await b.close();
      });
    },
  );
}
