/// UNIT (NOT e2e): exercises the REAL [AppiumBackend] over a MOCKED
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
  group('AppiumBackend.enterText masked flag (element-type-derived)', () {
    late List<String> hits;

    // A backend wired to a MockClient that reports the given element `type`.
    AppiumBackend backendReporting(String elementType) {
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
      return AppiumBackend(
        platform: 'ios',
        udid: 'U',
        app: '/x/Runner.app',
        client: client,
      );
    }

    test(
      'SecureTextField -> masked:true, reads attribute/type (not /name)',
      () async {
        final AppiumBackend b = backendReporting(
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
        final AppiumBackend b = backendReporting('XCUIElementTypeTextField');
        await b.connect();
        final ({String readback, bool masked}) r = await b.enterText(
          const NativeTarget(elementId: 'E', via: 'xpath'),
          'hello@example.com',
        );
        expect(r.masked, isFalse);
        expect(r.readback, 'hello@example.com');
        await b.close();
      },
    );
  });
}
