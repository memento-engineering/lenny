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

    test('resourceId is carried for named nodes and null for anonymous', () {
      // The stable, non-localising key Dart consumers need for overlay
      // detection: label/identifier both localise, resource-id does not.
      expect(_byLabel(nodes, 'Email address').resourceId, 'username');
      expect(
        nodes.first.resourceId,
        'com.nicospencer.lennyspike:id/login_button',
        reason:
            'the package-qualified form must survive verbatim — that is '
            'what a consumer matches on',
      );
      // The Password EditText has no resource-id in the fixture, which is
      // exactly why its xpath is positional.
      final NativeNode pw = _byLabel(nodes, 'Password');
      expect(pw.resourceId, isNull);
      expect(pw.xpath, '(//android.widget.EditText)[2]');
    });

    test('resourceId is NOT emitted to the wire record', () {
      // toRecord() is the canonical CROSS-HOST schema and must stay
      // byte-identical to leonard_flutter's semantics fragment, which has no
      // resource-id to emit. Wiring it would break that parity for a key the
      // model does not need — it addresses nodes by identifier/label. This is
      // the invariant, not a detail: it fails the moment someone helpfully
      // adds resourceId to toRecord().
      final NativeNode email = _byLabel(nodes, 'Email address');
      expect(email.resourceId, isNotNull);
      expect(email.toRecord().containsKey('resourceId'), isFalse);
      expect(email.toRecord().containsKey('resource-id'), isFalse);
      expect(email.toRecord().keys.toList(), <String>[
        'id',
        'role',
        'rect',
        'label',
        'identifier',
      ]);
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
      String keyboardShown = 'true',
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
        } else if (path.endsWith('/is_keyboard_shown')) {
          value = keyboardShown;
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

    test('NO back is issued when no soft keyboard is up', () async {
      // THE REGRESSION. `back` is Android's dismiss gesture only while a
      // keyboard holds focus; with none up it is plain navigation. setValue /
      // mobile: type do not raise the keyboard, so on a Chrome page an
      // unconditional back navigated the Custom Tab away and stranded the
      // whole flow — every later field lookup 404'd against a page that was
      // no longer showing.
      final UiAutomator2Backend b = backendReporting(
        password: 'false',
        text: 'hi',
        keyboardShown: 'false',
      );
      await b.connect();
      await b.enterText(const NativeTarget(elementId: 'E', via: 'xpath'), 'hi');
      expect(hits, contains('GET /session/s1/appium/device/is_keyboard_shown'));
      expect(
        hits,
        isNot(contains('POST /session/s1/back')),
        reason: 'a bare back with no keyboard up is navigation, not a dismiss',
      );
      await b.close();
    });

    test('an unreadable keyboard state presses nothing (fail safe)', () async {
      // The probe itself failing must NOT fall through to a press. A keyboard
      // left up is trivially recoverable; a spurious back is not. Without this
      // the existing `on Object` catch-all would silently restore the old
      // destructive behaviour on any transport hiccup.
      hits = <String>[];
      final MockClient client = MockClient((http.Request req) async {
        final String path = req.url.path;
        hits.add('${req.method} $path');
        if (path.endsWith('/is_keyboard_shown')) {
          return http.Response('gateway exploded', 502);
        }
        return http.Response(
          jsonEncode(<String, Object?>{
            'value': req.method == 'POST' && path == '/session'
                ? <String, Object?>{'sessionId': 's1'}
                : '',
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      final UiAutomator2Backend b = UiAutomator2Backend(
        udid: 'emulator-5554',
        app: 'com.example.app',
        client: client,
      );
      await b.connect();
      // The type itself must still succeed — dismiss is best-effort (B6).
      await b.enterText(const NativeTarget(elementId: 'E', via: 'xpath'), 'hi');
      expect(hits, contains('GET /session/s1/appium/device/is_keyboard_shown'));
      expect(hits, isNot(contains('POST /session/s1/back')));
      await b.close();
    });
  });

  group('UiAutomator2Backend.enterText ACTION_SET_TEXT fallback', () {
    late List<String> hits;
    late List<String> bodies;

    /// A backend whose `POST /element/{id}/value` answers with the W3C error
    /// [valueError], or succeeds when it is null. Chrome web-content inputs
    /// answer `invalid element state`: UiAutomator2 implements `/value` as
    /// `performAction(ACTION_SET_TEXT)`, which Chrome's `<input>` nodes refuse.
    /// [valueErrorBody] false reproduces a bare non-2xx with no error body, so
    /// the codeless path is reachable.
    UiAutomator2Backend backendWhereValueFails({
      String? valueError,
      bool valueErrorBody = true,
      String readback = 'user@example.com',
      bool focusedAfterClick = true,
    }) {
      hits = <String>[];
      bodies = <String>[];
      final MockClient client = MockClient((http.Request req) async {
        final String path = req.url.path;
        hits.add('${req.method} $path');
        bodies.add(req.body);
        final bool isValueWrite =
            req.method == 'POST' && path == '/session/s1/element/E/value';
        if (isValueWrite && !valueErrorBody) {
          return http.Response('upstream exploded', 500);
        }
        if (isValueWrite && valueError != null) {
          return http.Response(
            jsonEncode(<String, Object?>{
              'value': <String, Object?>{
                'error': valueError,
                'message':
                    "Cannot set the element to '$readback'. "
                    'Did you interact with the correct element?',
                'stacktrace':
                    'io.appium.uiautomator2.handler.SendKeysToElement'
                    '.setText(SendKeysToElement.java:87)',
              },
            }),
            400,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        Object? value;
        if (req.method == 'POST' && path == '/session') {
          value = <String, Object?>{'sessionId': 's1'};
        } else if (path.endsWith('/attribute/password')) {
          value = 'false';
        } else if (path.endsWith('/attribute/focused')) {
          value = focusedAfterClick ? 'true' : 'false';
        } else if (path.endsWith('/is_keyboard_shown')) {
          value = 'true';
        } else if (path.endsWith('/attribute/text')) {
          value = readback;
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

    test('invalid element state falls back to click + mobile: type', () async {
      final UiAutomator2Backend b = backendWhereValueFails(
        valueError: 'invalid element state',
      );
      await b.connect();
      final ({String readback, bool masked}) r = await b.enterText(
        const NativeTarget(elementId: 'E', via: 'xpath'),
        'user@example.com',
      );

      // The whole sequence, in order. Asserting only "it returned" would
      // pass against a fallback that typed the wrong thing, skipped the
      // clear, or never read back. The CLICK is asserted because it is
      // load-bearing: measured on device, `mobile: type` against an
      // unfocused element returns 200 and types nothing.
      expect(hits, <String>[
        'POST /session',
        'POST /session/s1/element/E/clear',
        'POST /session/s1/element/E/value',
        'POST /session/s1/element/E/click',
        'GET /session/s1/element/E/attribute/focused',
        'POST /session/s1/execute/sync',
        'GET /session/s1/element/E/attribute/password',
        'GET /session/s1/element/E/attribute/text',
        'GET /session/s1/appium/device/is_keyboard_shown',
        'POST /session/s1/back',
      ]);
      // The text must reach `mobile: type` verbatim.
      expect(
        jsonDecode(bodies[hits.indexOf('POST /session/s1/execute/sync')]),
        <String, Object?>{
          'script': 'mobile: type',
          'args': <Object?>[
            <String, Object?>{'text': 'user@example.com'},
          ],
        },
      );
      // `/keys` must NOT be used: it shares the ACTION_SET_TEXT handler for
      // arbitrary text and fails with the same error on a real device.
      expect(hits, isNot(contains('POST /session/s1/keys')));
      // The seam's record is identical to the happy path's.
      expect(r.readback, 'user@example.com');
      expect(r.masked, isFalse);
      await b.close();
    });

    test('a different remote error propagates and does NOT type', () async {
      final UiAutomator2Backend b = backendWhereValueFails(
        valueError: 'stale element reference',
      );
      await b.connect();
      await expectLater(
        b.enterText(const NativeTarget(elementId: 'E', via: 'xpath'), 'abc'),
        throwsA(
          isA<NativeException>()
              .having(
                (NativeException e) => e.code,
                'code',
                'stale element reference',
              )
              // The message keeps the code as a prefix: it is model-facing, so
              // adding `code` must not change what the agent reads.
              .having(
                (NativeException e) => e.message,
                'message',
                startsWith('stale element reference: '),
              ),
        ),
      );
      expect(
        hits,
        isNot(contains('POST /session/s1/execute/sync')),
        reason: 'the fallback must not swallow unrelated failures',
      );
      await b.close();
    });

    test('a codeless transport failure propagates and does NOT type', () async {
      // Proves `code` is a real discriminator rather than always-set: a bare
      // non-2xx carries none, so the fallback must not fire.
      final UiAutomator2Backend b = backendWhereValueFails(
        valueErrorBody: false,
      );
      await b.connect();
      await expectLater(
        b.enterText(const NativeTarget(elementId: 'E', via: 'xpath'), 'abc'),
        throwsA(
          isA<NativeException>().having(
            (NativeException e) => e.code,
            'code',
            isNull,
          ),
        ),
      );
      expect(hits, isNot(contains('POST /session/s1/execute/sync')));
      await b.close();
    });

    test(
      'an unfocusable field fails loudly instead of typing into the void',
      () async {
        // The obstructed case (measured on device: Chrome's Touch-To-Fill
        // sheet both refuses ACTION_SET_TEXT and swallows injected
        // keystrokes). `mobile: type` would report success and write nothing,
        // and for a MASKED field an empty readback is indistinguishable from a
        // correct write — so the guard has to fire BEFORE typing.
        final UiAutomator2Backend b = backendWhereValueFails(
          valueError: 'invalid element state',
          focusedAfterClick: false,
        );
        await b.connect();
        await expectLater(
          b.enterText(
            const NativeTarget(elementId: 'E', via: 'xpath'),
            'user@example.com',
          ),
          throwsA(
            isA<NativeException>().having(
              (NativeException e) => e.message,
              'message',
              allOf(
                contains('could not focus'),
                // The message must name the likely cause; a bare "failed"
                // leaves the caller with nothing to act on.
                contains('Touch-To-Fill'),
              ),
            ),
          ),
        );
        expect(
          hits,
          isNot(contains('POST /session/s1/execute/sync')),
          reason: 'must not type when the field could not be focused',
        );
        await b.close();
      },
    );

    test('the happy path types nothing extra', () async {
      final UiAutomator2Backend b = backendWhereValueFails(readback: 'hi');
      await b.connect();
      final ({String readback, bool masked}) r = await b.enterText(
        const NativeTarget(elementId: 'E', via: 'xpath'),
        'hi',
      );
      expect(hits, contains('POST /session/s1/element/E/value'));
      expect(
        hits,
        isNot(contains('POST /session/s1/element/E/click')),
        reason: 'the fallback must cost nothing when ACTION_SET_TEXT works',
      );
      expect(hits, isNot(contains('POST /session/s1/execute/sync')));
      expect(r.readback, 'hi');
      await b.close();
    });
  });
}
