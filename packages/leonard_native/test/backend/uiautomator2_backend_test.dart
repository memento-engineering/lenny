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

File _sheetFixture() {
  for (final String p in <String>[
    'test/fixtures/auth0_android_source_sheet_up.xml',
    'packages/leonard_native/test/fixtures/auth0_android_source_sheet_up.xml',
  ]) {
    final File f = File(p);
    if (f.existsSync()) return f;
  }
  fail('auth0_android_source_sheet_up.xml fixture not found');
}

File _permissionDialogFixture() {
  for (final String p in <String>[
    'test/fixtures/android_permission_dialog_source.xml',
    'packages/leonard_native/test/fixtures/android_permission_dialog_source.xml',
  ]) {
    final File f = File(p);
    if (f.existsSync()) return f;
  }
  fail('android_permission_dialog_source.xml fixture not found');
}

File _flutterSemanticsFixture() {
  for (final String p in <String>[
    'test/fixtures/flutter_android_semantics_source.xml',
    'packages/leonard_native/test/fixtures/flutter_android_semantics_source.xml',
  ]) {
    final File f = File(p);
    if (f.existsSync()) return f;
  }
  fail('flutter_android_semantics_source.xml fixture not found');
}

NativeNode _byLabel(List<NativeNode> nodes, String label) =>
    nodes.firstWhere((NativeNode n) => n.label == label);

void main() {
  test(
    'resource-id resolves first through W3C id with verbatim value',
    () async {
      final List<Map<String, Object?>> findBodies = <Map<String, Object?>>[];
      final MockClient client = MockClient((http.Request req) async {
        Object? value;
        if (req.url.path == '/session') {
          value = <String, Object?>{'sessionId': 's1'};
        } else if (req.url.path == '/session/s1/element') {
          findBodies.add((jsonDecode(req.body) as Map).cast<String, Object?>());
          value = <String, Object?>{
            'element-6066-11e4-a52e-4f735466cecf': 'E-resource',
          };
        }
        return http.Response(
          jsonEncode(<String, Object?>{'value': value}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      final UiAutomator2Backend backend = UiAutomator2Backend(
        udid: 'emulator-5554',
        app: 'com.example.app',
        platformVersion: '13',
        client: client,
      );
      await backend.connect();
      final NativeTarget? target = await backend.resolve(
        const NativeSelector(
          resourceId: "com.example:id/owner's_button",
          a11yId: 'must-not-run',
        ),
        null,
      );
      expect(target?.via, 'resource-id');
      expect(findBodies, <Map<String, Object?>>[
        <String, Object?>{
          'using': 'id',
          'value': "com.example:id/owner's_button",
        },
      ]);
      await backend.close();
    },
  );

  group('resource-id web-content fallback (GitHub #51)', () {
    // One MockClient shape for the group: `using=id` finds miss (a 200 with
    // a null value — _find's immediate-miss path), `using=xpath` finds hit.
    (UiAutomator2Backend, List<Map<String, Object?>>) rig() {
      final List<Map<String, Object?>> findBodies = <Map<String, Object?>>[];
      final MockClient client = MockClient((http.Request req) async {
        Object? value;
        if (req.url.path == '/session') {
          value = <String, Object?>{'sessionId': 's1'};
        } else if (req.url.path == '/session/s1/element') {
          final Map<String, Object?> body = (jsonDecode(req.body) as Map)
              .cast<String, Object?>();
          findBodies.add(body);
          value = body['using'] == 'xpath'
              ? <String, Object?>{
                  'element-6066-11e4-a52e-4f735466cecf': 'E-web',
                }
              : null;
        }
        return http.Response(
          jsonEncode(<String, Object?>{'value': value}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      return (
        UiAutomator2Backend(
          udid: 'emulator-5554',
          app: 'com.example.app',
          platformVersion: '13',
          client: client,
        ),
        findBodies,
      );
    }

    test('a bare id that misses on using=id falls through to xpath and '
        'resolves via resource-id-xpath', () async {
      final (UiAutomator2Backend backend, List<Map<String, Object?>> finds) =
          rig();
      await backend.connect();
      final NativeTarget? target = await backend.resolve(
        const NativeSelector(resourceId: 'email'),
        null,
      );
      expect(target?.elementId, 'E-web');
      expect(target?.via, 'resource-id-xpath');
      expect(finds, <Map<String, Object?>>[
        <String, Object?>{'using': 'id', 'value': 'email'},
        <String, Object?>{
          'using': 'xpath',
          'value': "//*[@resource-id='email']",
        },
      ]);
      await backend.close();
    });

    test('a pkg:id/name value that misses does NOT issue the xpath '
        'fallback — a missed native id is a genuine miss', () async {
      final (UiAutomator2Backend backend, List<Map<String, Object?>> finds) =
          rig();
      await backend.connect();
      final NativeTarget? target = await backend.resolve(
        const NativeSelector(resourceId: 'com.android.chrome:id/email'),
        null,
      );
      expect(target, isNull);
      expect(finds, <Map<String, Object?>>[
        <String, Object?>{
          'using': 'id',
          'value': 'com.android.chrome:id/email',
        },
      ]);
      await backend.close();
    });

    test('the fallback xpath literal is correctly quoted for a value '
        'carrying both quote kinds', () async {
      final (UiAutomator2Backend backend, List<Map<String, Object?>> finds) =
          rig();
      await backend.connect();
      final NativeTarget? target = await backend.resolve(
        const NativeSelector(resourceId: 'a\'b"c'),
        null,
      );
      expect(target?.via, 'resource-id-xpath');
      expect(finds.last, <String, Object?>{
        'using': 'xpath',
        'value': '//*[@resource-id=concat(\'a\', "\'", \'b"c\')]',
      });
      await backend.close();
    });
  });

  group('UiAutomator2Backend.connect capabilities', () {
    test(
      'omits an unknown version and records the explicit sentinel',
      () async {
        Map<String, Object?>? alwaysMatch;
        final UiAutomator2Backend backend = UiAutomator2Backend(
          udid: 'pixel',
          app: 'com.example.app',
          client: MockClient((http.Request request) async {
            final Map<String, Object?> body =
                jsonDecode(request.body) as Map<String, Object?>;
            final Map<String, Object?> capabilities =
                body['capabilities']! as Map<String, Object?>;
            alwaysMatch = capabilities['alwaysMatch']! as Map<String, Object?>;
            return http.Response(
              jsonEncode(<String, Object?>{
                'value': <String, Object?>{'sessionId': 'android-session'},
              }),
              200,
            );
          }),
        );

        await backend.connect();
        expect(alwaysMatch, isNot(contains('appium:platformVersion')));
        expect(
          backend.sessionProvenance?.androidVersion,
          AndroidSessionProvenance.unknownAndroidVersion,
        );
        await backend.close();
      },
    );

    test('merges safe extras into the complete session request', () async {
      http.Request? sessionRequest;
      final MockClient client = MockClient((http.Request request) async {
        sessionRequest = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'value': <String, Object?>{'sessionId': 'android-session'},
          }),
          200,
        );
      });
      final UiAutomator2Backend backend = UiAutomator2Backend(
        udid: 'pixel',
        app: 'com.example.app',
        platformVersion: '13',
        client: client,
      );

      await backend.connect(
        extraCapabilities: <String, Object?>{
          'appium:autoGrantPermissions': true,
          'appium:unicodeKeyboard': true,
          'appium:resetKeyboard': true,
          'appium:newCommandTimeout': 180,
        },
      );

      expect(sessionRequest?.method, 'POST');
      expect(sessionRequest?.url.path, '/session');
      final Map<String, Object?> body =
          jsonDecode(sessionRequest!.body) as Map<String, Object?>;
      final Map<String, Object?> capabilities =
          body['capabilities']! as Map<String, Object?>;
      expect(capabilities['alwaysMatch'], <String, Object?>{
        'platformName': 'Android',
        'appium:automationName': 'UiAutomator2',
        'appium:udid': 'pixel',
        'appium:platformVersion': '13',
        'appium:noReset': true,
        'appium:autoLaunch': false,
        'appium:newCommandTimeout': 180,
        'appium:autoGrantPermissions': true,
        'appium:unicodeKeyboard': true,
        'appium:resetKeyboard': true,
      });
      expect(capabilities['firstMatch'], <Object?>[<String, Object?>{}]);
    });

    test('retains returned device provenance until close', () async {
      final UiAutomator2Backend backend = UiAutomator2Backend(
        udid: 'requested-serial',
        app: 'com.example.app',
        platformVersion: '12',
        client: MockClient((http.Request request) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'value': <String, Object?>{
                'sessionId': 'android-session',
                'capabilities': <String, Object?>{
                  'appium:udid': 'R58M123',
                  'platformVersion': '13',
                  'appium:deviceManufacturer': 'samsung',
                  'deviceModel': 'SM-M225FV',
                },
              },
            }),
            200,
          );
        }),
      );

      await backend.connect();
      expect(backend.sessionProvenance?.deviceSerial, 'R58M123');
      expect(backend.sessionProvenance?.androidVersion, '13');
      expect(backend.sessionProvenance?.manufacturer, 'samsung');
      expect(backend.sessionProvenance?.model, 'SM-M225FV');
      await backend.close();
      expect(backend.sessionProvenance, isNull);
    });

    test(
      'retains immutable returned capabilities only while connected',
      () async {
        final UiAutomator2Backend backend = UiAutomator2Backend(
          udid: 'RF8RB21P6LN',
          app: 'com.example.sample_app',
          client: MockClient((http.Request request) async {
            return http.Response(
              jsonEncode(<String, Object?>{
                'value': <String, Object?>{
                  'sessionId': 'android-session',
                  'capabilities': <String, Object?>{
                    'appium:udid': 'RF8RB21P6LN',
                    'printPageSourceOnFindFailure': true,
                  },
                },
              }),
              200,
            );
          }),
        );

        expect(backend.sessionCapabilities, isNull);
        await backend.connect(
          extraCapabilities: const <String, Object?>{
            'appium:printPageSourceOnFindFailure': true,
          },
        );
        expect(
          backend.sessionCapabilities,
          containsPair('printPageSourceOnFindFailure', true),
        );
        expect(
          () => backend.sessionCapabilities!['new'] = true,
          throwsUnsupportedError,
        );
        await backend.close();
        expect(backend.sessionCapabilities, isNull);
      },
    );

    test(
      'requested version supplies provenance when Appium omits it',
      () async {
        final UiAutomator2Backend backend = UiAutomator2Backend(
          udid: 'requested-serial',
          app: 'com.example.app',
          platformVersion: '13',
          client: MockClient(
            (http.Request request) async => http.Response(
              jsonEncode(<String, Object?>{
                'value': <String, Object?>{
                  'sessionId': 'android-session',
                  'capabilities': <String, Object?>{},
                },
              }),
              200,
            ),
          ),
        );

        await backend.connect();
        expect(backend.sessionProvenance?.deviceSerial, 'requested-serial');
        expect(backend.sessionProvenance?.androidVersion, '13');
        expect(backend.sessionProvenance?.manufacturer, isNull);
        expect(backend.sessionProvenance?.model, isNull);
        await backend.close();
      },
    );

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
        final UiAutomator2Backend backend = UiAutomator2Backend(
          udid: 'pixel',
          app: 'com.example.app',
          platformVersion: '13',
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

    test('validates denied extras before an idempotent return', () async {
      int requests = 0;
      final UiAutomator2Backend backend = UiAutomator2Backend(
        udid: 'pixel',
        app: 'com.example.app',
        platformVersion: '13',
        client: MockClient((http.Request request) async {
          requests++;
          return http.Response(
            jsonEncode(<String, Object?>{
              'value': <String, Object?>{'sessionId': 'android-session'},
            }),
            200,
          );
        }),
      );

      await backend.connect();
      expect(requests, 1);

      await expectLater(
        backend.connect(
          extraCapabilities: const <String, Object?>{'appium:autoLaunch': true},
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(requests, 1);
    });
  });

  group('UiAutomator2Backend.parseSource', () {
    late List<NativeNode> nodes;

    setUpAll(() {
      final UiAutomator2Backend backend = UiAutomator2Backend(
        udid: 'fixture',
        app: 'com.example.app',
        platformVersion: '13',
      );
      nodes = backend.parseSource(_fixture().readAsStringSync());
      // Free the http.Client the constructor opened.
      backend.close();
    });

    test('preserves the measured Flutter Semantics Android projection', () {
      final UiAutomator2Backend backend = UiAutomator2Backend(
        udid: 'fixture',
        app: 'com.example.app',
        platformVersion: '13',
      );
      final List<NativeNode> flutterNodes = backend.parseSource(
        _flutterSemanticsFixture().readAsStringSync(),
      );
      backend.close();

      expect(flutterNodes, hasLength(4));
      expect(flutterNodes[0].resourceId, 'PrimaryFooterButtonKey');
      expect(flutterNodes[0].a11yId, isNull);
      expect(flutterNodes[1].role, 'button');
      expect(flutterNodes[1].resourceId, isNull);
      expect(flutterNodes[1].a11yId, isNull);
      expect(flutterNodes[2].resourceId, 'allow');
      expect(flutterNodes[2].a11yId, isNull);
      expect(flutterNodes[3].resourceId, isNull);
      expect(flutterNodes[3].a11yId, 'Allow');
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
        platformVersion: '13',
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
        platformVersion: '13',
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
        platformVersion: '13',
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
        platformVersion: '13',
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
      String keyboardShown = 'true',
      String? sourceXml,
      bool sourceFails = false,
      ObstructionResourceIdPolicy? obstructionIds,
    }) {
      hits = <String>[];
      bodies = <String>[];
      final MockClient client = MockClient((http.Request req) async {
        final String path = req.url.path;
        hits.add('${req.method} $path');
        bodies.add(req.body);
        if (sourceFails && path == '/session/s1/source') {
          return http.Response('upstream exploded', 500);
        }
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
          value = keyboardShown;
        } else if (path.endsWith('/attribute/text')) {
          value = readback;
        } else if (path == '/session/s1/source') {
          value = sourceXml ?? _fixture().readAsStringSync();
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
        platformVersion: '13',
        obstructionIds: obstructionIds,
        client: client,
      );
    }

    test('sheet obstruction is detected before click and type', () async {
      final UiAutomator2Backend b = backendWhereValueFails(
        valueError: 'invalid element state',
        sourceXml: _sheetFixture().readAsStringSync(),
      );
      await b.connect();
      await expectLater(
        b.enterText(const NativeTarget(elementId: 'E', via: 'xpath'), 'abc'),
        throwsA(
          isA<NativeException>()
              .having(
                (NativeException e) => e.code,
                'code',
                NativeException.fieldObscuredCode,
              )
              .having(
                (NativeException e) => e.message,
                'message',
                contains('Chrome Touch-To-Fill sheet'),
              ),
        ),
      );
      expect(hits.where((String h) => h.endsWith('/source')), hasLength(1));
      expect(hits, isNot(contains('POST /session/s1/element/E/click')));
      expect(hits, isNot(contains('POST /session/s1/execute/sync')));
      await b.close();
    });

    test('permission dialog is detected before click and type', () async {
      final UiAutomator2Backend b = backendWhereValueFails(
        valueError: 'invalid element state',
        sourceXml: _permissionDialogFixture().readAsStringSync(),
      );
      await b.connect();
      await expectLater(
        b.enterText(const NativeTarget(elementId: 'E', via: 'xpath'), 'abc'),
        throwsA(
          isA<NativeException>()
              .having(
                (NativeException e) => e.code,
                'code',
                NativeException.fieldObscuredCode,
              )
              .having(
                (NativeException e) => e.message,
                'message',
                contains('field is obscured by Android permission dialog'),
              ),
        ),
      );
      expect(hits, isNot(contains('POST /session/s1/element/E/click')));
      expect(hits, isNot(contains('POST /session/s1/back')));
      await b.close();
    });

    test('Google permission-controller prefix is detected', () async {
      final UiAutomator2Backend b = backendWhereValueFails(
        valueError: 'invalid element state',
        sourceXml: _permissionDialogFixture().readAsStringSync().replaceAll(
          'com.android.permissioncontroller',
          'com.google.android.permissioncontroller',
        ),
      );
      await b.connect();
      await expectLater(
        b.enterText(const NativeTarget(elementId: 'E', via: 'xpath'), 'abc'),
        throwsA(
          isA<NativeException>().having(
            (NativeException e) => e.code,
            'code',
            NativeException.fieldObscuredCode,
          ),
        ),
      );
      await b.close();
    });

    for (final String packageName in const <String>[
      'com.android.chrome',
      'com.chrome.beta',
      'com.chrome.dev',
      'com.chrome.canary',
    ]) {
      test('$packageName Chrome-family sheet is detected', () async {
        final UiAutomator2Backend b = backendWhereValueFails(
          valueError: 'invalid element state',
          sourceXml: _sheetFixture().readAsStringSync().replaceAll(
            'com.android.chrome',
            packageName,
          ),
        );
        await b.connect();
        await expectLater(
          b.enterText(const NativeTarget(elementId: 'E', via: 'xpath'), 'abc'),
          throwsA(
            isA<NativeException>().having(
              (NativeException e) => e.code,
              'code',
              NativeException.fieldObscuredCode,
            ),
          ),
        );
        await b.close();
      });
    }

    test('permission detection ignores every visible string', () async {
      final String sourceXml = _permissionDialogFixture().readAsStringSync();
      final List<String> visibleTextValues = RegExp(r'text="([^"]+)"')
          .allMatches(sourceXml)
          .map((RegExpMatch match) => match.group(1)!)
          .where((String value) => value.isNotEmpty)
          .toList();
      String localized = sourceXml;
      for (final String value in visibleTextValues) {
        localized = localized.replaceAll('text="$value"', 'text="ローカライズ済み"');
      }
      expect(visibleTextValues, isNotEmpty);
      expect(localized, isNot(sourceXml));
      final UiAutomator2Backend b = backendWhereValueFails(
        valueError: 'invalid element state',
        sourceXml: localized,
      );
      await b.connect();
      await expectLater(
        b.enterText(const NativeTarget(elementId: 'E', via: 'xpath'), 'abc'),
        throwsA(
          isA<NativeException>().having(
            (NativeException e) => e.message,
            'message',
            contains('field is obscured by Android permission dialog'),
          ),
        ),
      );
      expect(hits.where((String hit) => hit.endsWith('/click')), isEmpty);
      expect(hits, isNot(contains('POST /session/s1/back')));
      expect(hits, isNot(contains('POST /session/s1/execute/sync')));
      await b.close();
    });

    test(
      'a malformed real permission source never clicks a permission button',
      () async {
        final String captured = _permissionDialogFixture().readAsStringSync();
        const String buttonMarker = 'permission_allow_button';
        final int buttonEnd =
            captured.indexOf(buttonMarker) + buttonMarker.length;
        expect(buttonEnd, greaterThan(buttonMarker.length - 1));
        final String malformed = captured.substring(0, buttonEnd);
        expect(malformed, contains('com.google.android.permissioncontroller'));
        expect(malformed, contains(buttonMarker));

        final UiAutomator2Backend b = backendWhereValueFails(
          valueError: 'invalid element state',
          sourceXml: malformed,
          keyboardShown: 'false',
        );
        await b.connect();
        final ({String readback, bool masked}) result = await b.enterText(
          const NativeTarget(elementId: 'E', via: 'xpath'),
          'user@example.com',
        );
        expect(result.readback, 'user@example.com');
        expect(hits.where((String hit) => hit.endsWith('/click')), <String>[
          'POST /session/s1/element/E/click',
        ]);
        expect(hits, isNot(contains('POST /session/s1/element')));
        expect(hits, isNot(contains('POST /session/s1/back')));
        expect(
          hits.where((String hit) => hit.endsWith('/execute/sync')),
          <String>['POST /session/s1/execute/sync'],
        );
        await b.close();
      },
    );

    test('permission dialog dismissal refuses without posting Back', () async {
      final UiAutomator2Backend b = backendWhereValueFails(
        sourceXml: _permissionDialogFixture().readAsStringSync(),
      );
      await b.connect();
      await expectLater(
        b.press('dismiss_overlay'),
        throwsA(
          isA<NativeException>().having(
            (NativeException e) => e.message,
            'message',
            'Android permission dialog requires an explicit '
                'permission_allow or permission_deny press key',
          ),
        ),
      );
      expect(hits.where((String h) => h.endsWith('/source')), hasLength(1));
      expect(hits, isNot(contains('POST /session/s1/back')));
      await b.close();
    });

    for (final (String key, String resourceId) in <(String, String)>[
      (
        'permission_allow',
        'com.android.permissioncontroller:id/permission_allow_button',
      ),
      (
        'permission_deny',
        'com.android.permissioncontroller:id/permission_deny_button',
      ),
    ]) {
      test('$key finds its resource id and clicks only that element', () async {
        hits = <String>[];
        Map<String, Object?>? findBody;
        final MockClient client = MockClient((http.Request req) async {
          hits.add('${req.method} ${req.url.path}');
          Object? value;
          if (req.method == 'POST' && req.url.path == '/session') {
            value = <String, Object?>{'sessionId': 's1'};
          } else if (req.url.path == '/session/s1/source') {
            value =
                '<hierarchy><node resource-id="${resourceId.replaceFirst('com.android', 'com.google')}" /></hierarchy>';
          } else if (req.url.path == '/session/s1/element') {
            findBody = (jsonDecode(req.body) as Map).cast<String, Object?>();
            value = <String, Object?>{
              'element-6066-11e4-a52e-4f735466cecf': 'permission-button',
            };
          }
          return http.Response(
            jsonEncode(<String, Object?>{'value': value}),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        });
        final UiAutomator2Backend b = UiAutomator2Backend(
          udid: 'emulator-5554',
          app: 'com.example.app',
          platformVersion: '13',
          client: client,
        );
        await b.connect();
        await b.press(key);
        expect(findBody, <String, Object?>{
          'using': 'id',
          'value': resourceId.replaceFirst('com.android', 'com.google'),
        });
        expect(hits.where((String h) => h.endsWith('/click')), <String>[
          'POST /session/s1/element/permission-button/click',
        ]);
        await b.close();
      });
    }

    test('a missing permission button throws without clicking', () async {
      hits = <String>[];
      final MockClient client = MockClient((http.Request req) async {
        hits.add('${req.method} ${req.url.path}');
        final Object? value = switch (req.url.path) {
          '/session' => <String, Object?>{'sessionId': 's1'},
          '/session/s1/source' =>
            '<hierarchy><node resource-id="com.unrelated:id/permission_allow_button" /></hierarchy>',
          _ => null,
        };
        return http.Response(
          jsonEncode(<String, Object?>{'value': value}),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      final UiAutomator2Backend b = UiAutomator2Backend(
        udid: 'emulator-5554',
        app: 'com.example.app',
        platformVersion: '13',
        client: client,
      );
      await b.connect();
      await expectLater(
        b.press('permission_allow'),
        throwsA(
          isA<NativeException>().having(
            (NativeException e) => e.message,
            'message',
            'Android permission dialog button is not present: permission_allow',
          ),
        ),
      );
      expect(hits.where((String h) => h.endsWith('/click')), isEmpty);
      expect(hits.where((String h) => h.endsWith('/element')), isEmpty);
      await b.close();
    });

    test('custom policy detects vendor ids without visible text', () async {
      final ObstructionResourceIdPolicy vendorPolicy =
          ObstructionResourceIdPolicy(
            permissionDialogEntries: const <String>{'vendor_grant_surface'},
            permissionAllowEntries: const <String>{'vendor_allow'},
            permissionDenyEntries: const <String>{'vendor_deny'},
            chromeBottomSheetEntries: const <String>{'vendor_sheet'},
            chromeTouchToFillTitleEntries: const <String>{'vendor_sheet_title'},
            permissionPackage: (String value) => value == 'com.vendor.security',
            chromePackage: (String value) => value == 'com.vendor.browser',
          );
      final UiAutomator2Backend b = backendWhereValueFails(
        valueError: 'invalid element state',
        obstructionIds: vendorPolicy,
        sourceXml:
            '<hierarchy><node text="全く別の表示" content-desc="別" resource-id="com.vendor.security:id/vendor_grant_surface" /></hierarchy>',
      );
      await b.connect();
      await expectLater(
        b.enterText(const NativeTarget(elementId: 'E', via: 'xpath'), 'abc'),
        throwsA(
          isA<NativeException>().having(
            (NativeException e) => e.code,
            'code',
            NativeException.fieldObscuredCode,
          ),
        ),
      );
      await b.close();
    });

    // The obstruction probe is INSERTED into the `invalid element state`
    // handler, which every prior Android text-entry failure relied on to reach
    // the click + `mobile: type` fallback deterministically. Reading `/source`
    // introduces two brand-new ways for that handler to abort: a transport
    // failure (NativeException) and a malformed body (XmlParserException, which
    // would also escape the "backends only throw NativeException" invariant).
    // Detection must therefore fail SAFE toward NOT acting — the same direction
    // the keyboard gate takes — so an unreadable `/source` reads as "nothing
    // obstructing" and the pre-existing fallback still runs.
    test(
      'a /source transport failure still falls back to click + type',
      () async {
        final UiAutomator2Backend b = backendWhereValueFails(
          valueError: 'invalid element state',
          sourceFails: true,
        );
        await b.connect();
        final ({String readback, bool masked}) r = await b.enterText(
          const NativeTarget(elementId: 'E', via: 'xpath'),
          'user@example.com',
        );
        expect(r.readback, 'user@example.com');
        expect(hits, contains('POST /session/s1/element/E/click'));
        expect(hits, contains('POST /session/s1/execute/sync'));
        await b.close();
      },
    );

    test('a malformed /source body still falls back to click + type', () async {
      final UiAutomator2Backend b = backendWhereValueFails(
        valueError: 'invalid element state',
        // Truncated mid-node: XmlDocument.parse throws XmlParserException,
        // which is NOT a NativeException and would escape the tool layer's
        // `on NativeException catch` entirely.
        sourceXml: '<hierarchy><node class="android.widget.EditText"',
      );
      await b.connect();
      final ({String readback, bool masked}) r = await b.enterText(
        const NativeTarget(elementId: 'E', via: 'xpath'),
        'user@example.com',
      );
      expect(r.readback, 'user@example.com');
      expect(hits, contains('POST /session/s1/element/E/click'));
      expect(hits, contains('POST /session/s1/execute/sync'));
      await b.close();
    });

    test(
      'sheet detection ignores localized text and content description',
      () async {
        final String localized = _sheetFixture()
            .readAsStringSync()
            .replaceAll('Use saved password?', '保存したパスワードを使用？')
            .replaceAll(
              'List of credentials to be filled on touch.',
              'タッチで入力する認証情報の一覧。',
            );
        expect(localized, isNot(contains('Use saved password?')));
        expect(
          localized,
          isNot(
            contains(
              'content-desc="List of credentials to be filled on touch."',
            ),
          ),
        );
        final UiAutomator2Backend b = backendWhereValueFails(
          valueError: 'invalid element state',
          sourceXml: localized,
        );
        await b.connect();
        await expectLater(
          b.enterText(const NativeTarget(elementId: 'E', via: 'xpath'), 'abc'),
          throwsA(
            isA<NativeException>().having(
              (NativeException e) => e.code,
              'code',
              NativeException.fieldObscuredCode,
            ),
          ),
        );
        await b.close();
      },
    );

    test(
      'dismiss_overlay is positively gated and checked every time',
      () async {
        final UiAutomator2Backend sheet = backendWhereValueFails(
          valueError: 'invalid element state',
          sourceXml: _sheetFixture().readAsStringSync(),
        );
        await sheet.connect();
        for (var attempt = 0; attempt < 2; attempt++) {
          await expectLater(
            sheet.enterText(
              const NativeTarget(elementId: 'E', via: 'xpath'),
              'abc',
            ),
            throwsA(
              isA<NativeException>().having(
                (NativeException e) => e.code,
                'code',
                NativeException.fieldObscuredCode,
              ),
            ),
          );
          await sheet.press('dismiss_overlay');
        }
        expect(
          hits.where((String h) => h.endsWith('/source')),
          hasLength(4),
          reason: 'each write and each dismissal must independently detect',
        );
        expect(
          hits.where((String h) => h == 'POST /session/s1/back'),
          hasLength(2),
        );
        await sheet.close();

        final UiAutomator2Backend noSheet = backendWhereValueFails(
          sourceXml: _fixture().readAsStringSync(),
        );
        await noSheet.connect();
        await expectLater(
          noSheet.press('dismiss_overlay'),
          throwsA(isA<NativeException>()),
        );
        expect(hits, isNot(contains('POST /session/s1/back')));
        await noSheet.close();
      },
    );

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
        'GET /session/s1/source',
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
