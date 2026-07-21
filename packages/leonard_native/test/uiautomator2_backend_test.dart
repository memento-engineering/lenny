/// UNIT (NOT e2e): exercises the REAL [UiAutomator2Backend] against a checked-in
/// UiAutomator2 `/source` fixture and a MOCKED `http.Client` — no Appium server,
/// no emulator. Locks the three Android divergences the iOS tests cannot cover:
/// the `<hierarchy>` parse (class->role, `bounds`->rect, `content-desc` as the
/// tier-1 identifier, `resource-id`-or-positional xpath), the `back` press key,
/// and the `attribute/password`-derived masked flag.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:leonard_native/leonard_native.dart';
import 'package:test/test.dart';

/// Resolve the fixture from either invocation cwd (package root or repo root),
/// mirroring `appium_xml_parser_test.dart`'s dual-path resolver.
File _fixture() {
  for (final String p in <String>[
    'test/fixtures/auth0_android_source.xml',
    'packages/leonard_native/test/fixtures/auth0_android_source.xml',
  ]) {
    final File f = File(p);
    if (f.existsSync()) return f;
  }
  fail(
    'auth0_android_source.xml fixture not found from '
    '${Directory.current.path}',
  );
}

NativeNode _byLabel(List<NativeNode> nodes, String label) =>
    nodes.firstWhere((NativeNode n) => n.label == label);

void main() {
  group('UiAutomator2Backend.parseSource', () {
    late List<NativeNode> nodes;

    setUpAll(() {
      final UiAutomator2Backend backend = UiAutomator2Backend(
        udid: 'fixture',
        app: 'com.example.app',
      );
      nodes = backend.parseSource(_fixture().readAsStringSync());
      // Free the http.Client the constructor opened.
      backend.close();
    });

    test('flattens the a11y tree to the real controls in document order', () {
      // The FrameLayout scaffolding is dropped (no signal + default role); the
      // kept nodes are the real controls with dense 1-based document-order ids.
      expect(nodes.map((NativeNode n) => n.role).toList(), <String>[
        'button', // Log in
        'text', // opening Auth0…
        'text', // form (named container View)
        'image', // anonymous ImageView #1
        'textfield', // Email address
        'textfield', // Password
        'switch', // Show password
        'image', // anonymous ImageView #2
        'text', // Reset password (a web View, not an iOS link)
        'button', // SIGN IN
      ]);
      expect(nodes.map((NativeNode n) => n.id).toList(), <int>[
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
      ]);
      expect(nodes, hasLength(10));
    });

    test(
      'Log in button — bounds->rect, text label, content-desc identifier',
      () {
        final NativeNode logIn = nodes.first;
        expect(logIn.id, 1);
        expect(logIn.role, 'button');
        expect(logIn.label, 'Log in');
        expect(logIn.a11yId, 'Log in'); // content-desc == the tier-1 key
        expect(logIn.rect, <int>[
          156,
          450,
          246,
          498,
        ]); // [l,t][r,b] -> [l,t,r,b]
        expect(
          logIn.xpath,
          '//android.widget.Button[@resource-id='
          "'com.nicospencer.lennyspike:id/login_button']",
        );
        // Non-editable -> no `value`; xpath stays selector-internal.
        expect(logIn.toRecord(), <String, Object?>{
          'id': 1,
          'role': 'button',
          'rect': <int>[156, 450, 246, 498],
          'label': 'Log in',
          'identifier': 'Log in',
        });
      },
    );

    test('Email EditText — content-desc label fallback, value omitted', () {
      final NativeNode email = _byLabel(nodes, 'Email address');
      expect(email.role, 'textfield');
      // `text` is empty before typing, so the label falls back to content-desc.
      expect(email.label, 'Email address');
      expect(email.a11yId, 'Email address');
      expect(email.rect, <int>[40, 376, 362, 428]);
      expect(email.xpath, "//android.widget.EditText[@resource-id='username']");
      expect(email.value, isNull);
      expect(email.toRecord().containsKey('value'), isFalse);
      expect(email.toRecord()['identifier'], 'Email address');
    });

    test('Password EditText — no resource-id falls back to positional xpath', () {
      final NativeNode pw = _byLabel(nodes, 'Password');
      expect(pw.role, 'textfield');
      expect(pw.a11yId, 'Password');
      expect(pw.rect, <int>[41, 441, 317, 493]);
      // Second EditText among kept nodes of that class, and unnamed -> position.
      expect(pw.xpath, '(//android.widget.EditText)[2]');
    });

    test('anonymous nodes get deterministic positional xpath synthesis', () {
      final List<NativeNode> images = nodes
          .where((NativeNode n) => n.role == 'image')
          .toList();
      expect(images, hasLength(2));
      expect(images[0].a11yId, isNull);
      expect(images[0].toRecord().containsKey('identifier'), isFalse);
      expect(images[0].xpath, '(//android.widget.ImageView)[1]');
      expect(images[1].xpath, '(//android.widget.ImageView)[2]');
    });

    test('duplicate resource-ids fall through to positional xpath', () {
      // Two same-class, same-resource-id buttons: the uniqueness gate pushes
      // BOTH to positional, while a uniquely-identified sibling stays named.
      const String xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<hierarchy rotation="0">
  <android.widget.Button class="android.widget.Button" resource-id="ok" text="OK" bounds="[0,0][10,10]"/>
  <android.widget.Button class="android.widget.Button" resource-id="ok" text="OK" bounds="[0,20][10,30]"/>
  <android.widget.Button class="android.widget.Button" resource-id="cancel" text="Cancel" bounds="[0,40][10,50]"/>
</hierarchy>''';
      final UiAutomator2Backend backend = UiAutomator2Backend(
        udid: 'fixture',
        app: 'com.example.app',
      );
      final List<NativeNode> parsed = backend.parseSource(xml);
      backend.close();
      expect(parsed, hasLength(3));
      expect(parsed[0].xpath, '(//android.widget.Button)[1]');
      expect(parsed[1].xpath, '(//android.widget.Button)[2]');
      expect(parsed[2].xpath, "//android.widget.Button[@resource-id='cancel']");
    });
  });

  group('UiAutomator2Backend.press (Android key vocabulary)', () {
    late List<String> hits;

    UiAutomator2Backend backend() {
      hits = <String>[];
      final MockClient client = MockClient((http.Request req) async {
        final String path = req.url.path;
        hits.add('${req.method} $path');
        final Object? value = req.method == 'POST' && path == '/session'
            ? <String, Object?>{'sessionId': 's1'}
            : null;
        return http.Response(
          jsonEncode(<String, Object?>{'value': value}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      return UiAutomator2Backend(
        udid: 'emulator-5554',
        app: 'com.example.app',
        client: client,
      );
    }

    test('back -> POST /session/<sid>/back', () async {
      final UiAutomator2Backend b = backend();
      await b.connect();
      await b.press('back');
      expect(hits, contains('POST /session/s1/back'));
      await b.close();
    });

    test('enter -> POST /session/<sid>/keys', () async {
      final UiAutomator2Backend b = backend();
      await b.connect();
      await b.press('enter');
      expect(hits, contains('POST /session/s1/keys'));
      await b.close();
    });

    test(
      'iOS-only alert keys throw NativeException (no Android alert)',
      () async {
        final UiAutomator2Backend b = backend();
        await b.connect();
        // Android's Auth0 handoff is a Chrome Custom Tab — there is no
        // SpringBoard consent / Save-Password alert, so an adaptive caller sees
        // ok:false rather than a bogus success.
        await expectLater(
          () => b.press('consent_accept'),
          throwsA(isA<NativeException>()),
        );
        await expectLater(
          () => b.press('alert_dismiss'),
          throwsA(isA<NativeException>()),
        );
        await expectLater(
          () => b.press('wat'),
          throwsA(isA<NativeException>()),
        );
        expect(hits, isNot(contains('POST /session/s1/alert/accept')));
        await b.close();
      },
    );
  });

  group('UiAutomator2Backend.enterText masked flag (password-attr-derived)', () {
    late List<String> hits;

    // A backend wired to a MockClient reporting the given `password` attribute.
    UiAutomator2Backend backendReporting({
      required String password,
      required String text,
    }) {
      hits = <String>[];
      final MockClient client = MockClient((http.Request req) async {
        final String path = req.url.path;
        hits.add('${req.method} $path');
        Object? value;
        if (req.method == 'POST' && path == '/session') {
          value = <String, Object?>{'sessionId': 's1'};
        } else if (path.endsWith('/attribute/password')) {
          value = password;
        } else if (path.endsWith('/attribute/text')) {
          value = text;
        }
        return http.Response(
          jsonEncode(<String, Object?>{'value': value}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      return UiAutomator2Backend(
        udid: 'emulator-5554',
        app: 'com.example.app',
        client: client,
      );
    }

    test(
      'password="true" -> masked:true, reads attribute/text (not /value)',
      () async {
        // Android never exposes a secret through attribute/text — it reads back
        // EMPTY. `masked` must still be true, because it is attribute-derived.
        final UiAutomator2Backend b = backendReporting(
          password: 'true',
          text: '',
        );
        await b.connect();
        final ({String readback, bool masked}) r = await b.enterText(
          const NativeTarget(elementId: 'E', via: 'xpath'),
          'sup3r-secret',
        );
        expect(r.masked, isTrue);
        expect(r.readback, isNot('sup3r-secret')); // never the plaintext
        expect(hits, contains('GET /session/s1/element/E/attribute/password'));
        expect(hits, contains('GET /session/s1/element/E/attribute/text'));
        expect(
          hits,
          isNot(contains('GET /session/s1/element/E/attribute/value')),
        );
        // The keyboard dismiss is the Android back key, inside enterText.
        expect(hits, contains('POST /session/s1/back'));
        await b.close();
      },
    );

    test(
      'password="false" -> masked:false, readback is the typed value',
      () async {
        final UiAutomator2Backend b = backendReporting(
          password: 'false',
          text: 'hello@example.com',
        );
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
