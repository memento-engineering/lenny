/// UNIT (NOT e2e): the seam a consumer drives directly — `alertText`
/// (lenny#180), `activateApp` (lenny#182), `resolve`'s `findTimeout`
/// (lenny#183), `sessionId` (lenny#188), `parentId` (lenny#189), `rawSource`
/// and the Apple `disabled` state (lenny#190), `readAttribute` (lenny#191),
/// the if-present alert answers (lenny#192) and `enterText`'s
/// `dismissKeyboard` (lenny#193), `isPresent` (the #183 review) and an empty
/// find value read as a miss (lenny#200) — on each
/// REAL Appium backend over a MOCKED `http.Client`.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:leonard_native/leonard_native.dart';
import 'package:test/test.dart';

http.Response _json(Object? value, {int status = 200}) => http.Response(
  jsonEncode(<String, Object?>{'value': value}),
  status,
  headers: const <String, String>{'content-type': 'application/json'},
);

http.Response _w3cError(String error, {int status = 404}) => _json(
  <String, Object?>{'error': error, 'message': '$error (mocked)'},
  status: status,
);

/// One backend under test, built over [client].
typedef _Make = NativeBackend Function(http.Client client);

final Map<String, _Make> _backends = <String, _Make>{
  'XcuiTestBackend': (http.Client c) =>
      XcuiTestBackend(udid: 'U', app: '/x/Runner.app', client: c),
  'UiAutomator2Backend': (http.Client c) =>
      UiAutomator2Backend(udid: 'U', app: '/x/app.apk', client: c),
  'Mac2Backend': (http.Client c) =>
      Mac2Backend(bundleId: 'engineering.memento.Mac', client: c),
};

/// Answers session setup (create, and XCUITest's context switch), then
/// records every other request and hands it to [respond].
MockClient _client(
  List<http.Request> requests,
  Future<http.Response> Function(http.Request request) respond,
) => MockClient((http.Request request) async {
  if (request.url.path == '/session') {
    return _json(<String, Object?>{'sessionId': 's1'});
  }
  if (request.url.path == '/session/s1/context') return _json(null);
  requests.add(request);
  return respond(request);
});

void main() {
  group('alertText', () {
    for (final String name in <String>[
      'XcuiTestBackend',
      'UiAutomator2Backend',
    ]) {
      group(name, () {
        test('returns the open alert text', () async {
          final List<http.Request> requests = <http.Request>[];
          final NativeBackend backend = _backends[name]!(
            _client(requests, (_) async => _json('Allow notifications?')),
          );
          await backend.connect();
          requests.clear();

          expect(await backend.alertText(), 'Allow notifications?');
          expect(requests.single.method, 'GET');
          expect(requests.single.url.path, '/session/s1/alert/text');
          await backend.close();
        });

        test('maps W3C no such alert to null', () async {
          final NativeBackend backend = _backends[name]!(
            _client(<http.Request>[], (_) async => _w3cError('no such alert')),
          );
          await backend.connect();

          expect(await backend.alertText(), isNull);
          await backend.close();
        });

        test('any other failure is a NativeException', () async {
          final NativeBackend backend = _backends[name]!(
            _client(
              <http.Request>[],
              (_) async => _w3cError('unknown command', status: 405),
            ),
          );
          await backend.connect();

          await expectLater(
            backend.alertText(),
            throwsA(
              isA<NativeException>().having(
                (NativeException e) => e.code,
                'code',
                'unknown command',
              ),
            ),
          );
          await backend.close();
        });
      });
    }

    test('Mac2Backend refuses without transport I/O', () async {
      final List<http.Request> requests = <http.Request>[];
      final NativeBackend backend = _backends['Mac2Backend']!(
        _client(requests, (_) async => _json(null)),
      );
      await backend.connect();
      requests.clear();

      await expectLater(
        backend.alertText(),
        throwsA(
          isA<NativeException>().having(
            (NativeException e) => e.code,
            'code',
            'unsupported operation',
          ),
        ),
      );
      expect(requests, isEmpty);
      await backend.close();
    });
  });

  group('activateApp issues the driver command', () {
    final Map<String, (String, Map<String, Object?>)> expected =
        <String, (String, Map<String, Object?>)>{
          'XcuiTestBackend': (
            'mobile: activateApp',
            <String, Object?>{'bundleId': 'engineering.memento.Runner'},
          ),
          'UiAutomator2Backend': (
            'mobile: activateApp',
            <String, Object?>{'appId': 'engineering.memento.Runner'},
          ),
          'Mac2Backend': (
            'macos: activateApp',
            <String, Object?>{'bundleId': 'engineering.memento.Runner'},
          ),
        };
    for (final MapEntry<String, (String, Map<String, Object?>)> entry
        in expected.entries) {
      test(entry.key, () async {
        final List<http.Request> requests = <http.Request>[];
        final NativeBackend backend = _backends[entry.key]!(
          _client(requests, (_) async => _json(null)),
        );
        await backend.connect();
        requests.clear();

        await backend.activateApp('engineering.memento.Runner');

        expect(requests.single.url.path, '/session/s1/execute/sync');
        expect(jsonDecode(requests.single.body), <String, Object?>{
          'script': entry.value.$1,
          'args': <Object?>[entry.value.$2],
        });
        await backend.close();
      });
    }
  });

  group('resolve with findTimeout zero makes one find per populated tier', () {
    for (final String name in _backends.keys) {
      test(name, () async {
        final List<http.Request> finds = <http.Request>[];
        final NativeBackend backend = _backends[name]!(
          _client(<http.Request>[], (http.Request request) async {
            if (!request.url.path.endsWith('/element')) return _json(null);
            finds.add(request);
            return _w3cError('no such element');
          }),
        );
        await backend.connect();

        final Stopwatch clock = Stopwatch()..start();
        final NativeTarget? target = await backend.resolve(
          const NativeSelector(a11yId: 'passkey-prompt', xpath: '//Sheet'),
          null,
          findTimeout: Duration.zero,
        );

        expect(target, isNull);
        expect(
          finds.map((http.Request r) => jsonDecode(r.body)['using']),
          <String>['accessibility id', 'xpath'],
        );
        // Well under one retry interval: no tier waited.
        expect(clock.elapsed, lessThan(const Duration(milliseconds: 400)));
        await backend.close();
      });
    }

    test('a hit on the single attempt still resolves', () async {
      final NativeBackend backend = _backends['XcuiTestBackend']!(
        _client(
          <http.Request>[],
          (_) async => _json(<String, Object?>{
            'element-6066-11e4-a52e-4f735466cecf': 'E1',
          }),
        ),
      );
      await backend.connect();

      final NativeTarget? target = await backend.resolve(
        const NativeSelector(a11yId: 'passkey-prompt'),
        null,
        findTimeout: Duration.zero,
      );

      expect(target?.elementId, 'E1');
      expect(target?.via, 'a11y-id');
      await backend.close();
    });
  });

  group('sessionId follows the session', () {
    for (final String name in _backends.keys) {
      test(name, () async {
        final NativeBackend b = _backends[name]!(
          _client(<http.Request>[], (_) async => _json(null)),
        );
        String? sid() => switch (b) {
          final XcuiTestBackend x => x.sessionId,
          final UiAutomator2Backend a => a.sessionId,
          final Mac2Backend m => m.sessionId,
          _ => fail('unexpected backend'),
        };
        expect(sid(), isNull);
        await b.connect();
        expect(sid(), 's1');
        await b.close();
        expect(sid(), isNull);
      });
    }
  });

  group('readAttribute and rawSource', () {
    for (final String name in _backends.keys) {
      test(name, () async {
        final List<http.Request> requests = <http.Request>[];
        final NativeBackend b = _backends[name]!(
          _client(requests, (http.Request r) async {
            if (r.url.path.endsWith('/source')) return _json('<root/>');
            if (r.url.path.endsWith('/attribute/value')) return _json('a@b.c');
            return _json(null);
          }),
        );
        await b.connect();
        const NativeTarget field = NativeTarget(elementId: 'E1', via: 'xpath');

        expect(await b.readAttribute(field, 'value'), 'a@b.c');
        expect(await b.readAttribute(field, 'checked'), isNull);
        expect(
          requests.map((http.Request r) => '${r.method} ${r.url.path}'),
          containsAll(<String>[
            'GET /session/s1/element/E1/attribute/value',
            'GET /session/s1/element/E1/attribute/checked',
          ]),
        );
        await expectLater(
          b.readAttribute(
            const NativeTarget(point: (x: 1, y: 2), via: 'rect-center'),
            'value',
          ),
          throwsA(isA<NativeException>()),
        );
        expect(await b.rawSource(), '<root/>');
        await b.close();
      });
    }
  });

  group('the if-present alert answers', () {
    for (final String name in <String>[
      'XcuiTestBackend',
      'UiAutomator2Backend',
    ]) {
      test('$name: answered is true, no alert is false', () async {
        bool alertUp = true;
        final List<http.Request> requests = <http.Request>[];
        final NativeBackend b = _backends[name]!(
          _client(requests, (http.Request r) async {
            if (r.url.path.endsWith('/source')) return _json('<hierarchy/>');
            if (r.url.path.contains('/alert/')) {
              if (!alertUp) return _w3cError(NativeException.noSuchAlertCode);
              alertUp = false;
            }
            return _json(null);
          }),
        );
        await b.connect();

        expect(await b.acceptAlertIfPresent(), isTrue);
        expect(await b.dismissAlertIfPresent(), isFalse);
        expect(
          requests
              .where((http.Request r) => r.url.path.contains('/alert/'))
              .map((http.Request r) => r.url.path),
          <String>['/session/s1/alert/accept', '/session/s1/alert/dismiss'],
        );
        await b.close();
      });

      test('$name: any other failure throws', () async {
        final NativeBackend b = _backends[name]!(
          _client(<http.Request>[], (http.Request r) async {
            if (r.url.path.endsWith('/source')) return _json('<hierarchy/>');
            if (r.url.path.contains('/alert/')) {
              return _w3cError('unknown error', status: 500);
            }
            return _json(null);
          }),
        );
        await b.connect();

        await expectLater(
          b.dismissAlertIfPresent(),
          throwsA(isA<NativeException>()),
        );
        await b.close();
      });
    }

    test('Mac2Backend refuses without transport I/O', () async {
      final List<http.Request> requests = <http.Request>[];
      final NativeBackend b = _backends['Mac2Backend']!(
        _client(requests, (_) async => _json(null)),
      );
      await b.connect();
      requests.clear();

      for (final Future<bool> Function() answer in <Future<bool> Function()>[
        b.acceptAlertIfPresent,
        b.dismissAlertIfPresent,
      ]) {
        await expectLater(
          answer,
          throwsA(
            isA<NativeException>().having(
              (NativeException e) => e.code,
              'code',
              'unsupported operation',
            ),
          ),
        );
      }
      expect(requests, isEmpty);
      await b.close();
    });
  });

  group('enterText dismissKeyboard false skips the dismissal', () {
    test('XcuiTestBackend (iOS 17: no Done search)', () async {
      final List<http.Request> requests = <http.Request>[];
      final XcuiTestBackend b = XcuiTestBackend(
        udid: 'U',
        app: '/x/Runner.app',
        platformVersion: '17.5',
        client: _client(requests, (_) async => _json(null)),
      );
      await b.connect();
      const NativeTarget field = NativeTarget(elementId: 'E1', via: 'xpath');

      await b.enterText(field, 'x', dismissKeyboard: false);
      expect(requests.where((r) => r.url.path.endsWith('/element')), isEmpty);
      await b.enterText(field, 'x');
      expect(
        requests.where((r) => r.url.path.endsWith('/element')),
        isNotEmpty,
        reason: 'the default still looks for a Done key',
      );
      await b.close();
    });

    test('UiAutomator2Backend (no keyboard probe)', () async {
      final List<http.Request> requests = <http.Request>[];
      final NativeBackend b = _backends['UiAutomator2Backend']!(
        _client(requests, (_) async => _json(null)),
      );
      await b.connect();
      const NativeTarget field = NativeTarget(elementId: 'E1', via: 'xpath');
      bool probed() =>
          requests.any((r) => r.url.path.endsWith('/is_keyboard_shown'));

      await b.enterText(field, 'x', dismissKeyboard: false);
      expect(probed(), isFalse);
      await b.enterText(field, 'x');
      expect(probed(), isTrue);
      await b.close();
    });
  });

  group('parentId links each node to its nearest kept ancestor', () {
    // Two filtered containers sit between the app and the button; the text is
    // a sibling of the dropped window's subtree, one level up.
    test('XcuiTestBackend, with the disabled state', () {
      final XcuiTestBackend b = XcuiTestBackend(udid: 'U', app: '/x');
      final List<NativeNode> nodes = b.parseSource(
        '<XCUIElementTypeApplication type="XCUIElementTypeApplication" '
        'name="App"><XCUIElementTypeWindow type="XCUIElementTypeWindow">'
        '<XCUIElementTypeOther type="XCUIElementTypeOther">'
        '<XCUIElementTypeButton type="XCUIElementTypeButton" name="Go" '
        'enabled="false"/></XCUIElementTypeOther>'
        '<XCUIElementTypeStaticText type="XCUIElementTypeStaticText" '
        'label="Hi" enabled="true"/></XCUIElementTypeWindow>'
        '</XCUIElementTypeApplication>',
      );
      b.close();
      expect(
        nodes.map((NativeNode n) => (n.label, n.parentId, n.state)),
        <(String?, int?, List<String>)>[
          ('App', null, const <String>[]),
          ('Go', 1, const <String>['disabled']),
          ('Hi', 1, const <String>[]),
        ],
      );
      expect(nodes[1].toRecord()['state'], <String>['disabled']);
      expect(nodes[1].toRecord(), isNot(contains('parentId')));
    });

    test('UiAutomator2Backend', () {
      final UiAutomator2Backend b = UiAutomator2Backend(udid: 'U', app: '/x');
      final List<NativeNode> nodes = b.parseSource(
        '<hierarchy rotation="0"><android.widget.FrameLayout '
        'class="android.widget.FrameLayout" bounds="[0,0][9,9]">'
        '<android.view.View class="android.view.View" content-desc="Panel" '
        'bounds="[0,0][9,9]"><android.widget.LinearLayout '
        'class="android.widget.LinearLayout" bounds="[0,0][9,9]">'
        '<android.widget.Button class="android.widget.Button" text="Go" '
        'bounds="[0,0][9,9]"/></android.widget.LinearLayout></android.view.View>'
        '</android.widget.FrameLayout></hierarchy>',
      );
      b.close();
      expect(
        nodes.map((NativeNode n) => (n.label, n.parentId)),
        <(String?, int?)>[('Panel', null), ('Go', 1)],
      );
    });

    test('Mac2Backend, with the disabled state', () {
      final Mac2Backend b = Mac2Backend(bundleId: 'engineering.memento');
      final List<NativeNode> nodes = b.parseSource(
        '<XCUIElementTypeApplication type="XCUIElementTypeApplication" '
        'title="App"><XCUIElementTypeGroup type="XCUIElementTypeGroup">'
        '<XCUIElementTypeButton type="XCUIElementTypeButton" title="Go" '
        'enabled="false"/></XCUIElementTypeGroup>'
        '</XCUIElementTypeApplication>',
      );
      b.close();
      expect(
        nodes.map((NativeNode n) => (n.label, n.parentId, n.state)),
        <(String?, int?, List<String>)>[
          ('App', null, const <String>[]),
          ('Go', 1, const <String>['disabled']),
        ],
      );
    });
  });

  group('isPresent', () {
    final Map<String, String> labelQuery = <String, String>{
      'XcuiTestBackend': "//*[@label='Passkey' or @name='Passkey']",
      'UiAutomator2Backend': "//*[@text='Passkey' or @content-desc='Passkey']",
      'Mac2Backend': "//*[@label='Passkey' or @title='Passkey']",
    };
    for (final String name in _backends.keys) {
      test('$name: a gone element is absent, even with a rect', () async {
        // The #183 review: resolve(findTimeout: zero) would answer this with a
        // rect-center target. isPresent must not.
        final List<Map<String, Object?>> finds = <Map<String, Object?>>[];
        final NativeBackend b = _backends[name]!(
          _client(<http.Request>[], (http.Request r) async {
            if (!r.url.path.endsWith('/element')) return _json(null);
            finds.add((jsonDecode(r.body) as Map).cast<String, Object?>());
            return _w3cError('no such element');
          }),
        );
        await b.connect();

        final Stopwatch clock = Stopwatch()..start();
        final bool present = await b.isPresent(
          const NativeSelector(
            a11yId: 'passkey-prompt',
            label: 'Passkey',
            xpath: '//Sheet',
            rect: <int>[0, 0, 10, 10],
          ),
        );

        expect(present, isFalse);
        expect(clock.elapsed, lessThan(const Duration(milliseconds: 400)));
        expect(finds, <Map<String, Object?>>[
          <String, Object?>{
            'using': 'accessibility id',
            'value': 'passkey-prompt',
          },
          <String, Object?>{'using': 'xpath', 'value': labelQuery[name]},
          <String, Object?>{'using': 'xpath', 'value': '//Sheet'},
        ]);
        await b.close();
      });

      test('$name: the first hit answers present', () async {
        int finds = 0;
        final NativeBackend b = _backends[name]!(
          _client(<http.Request>[], (http.Request r) async {
            if (!r.url.path.endsWith('/element')) return _json(null);
            finds++;
            return _json(<String, Object?>{
              'element-6066-11e4-a52e-4f735466cecf': 'E1',
            });
          }),
        );
        await b.connect();

        expect(
          await b.isPresent(
            const NativeSelector(a11yId: 'passkey-prompt', xpath: '//Sheet'),
          ),
          isTrue,
        );
        expect(finds, 1);
        await b.close();
      });

      test('$name: an empty find value is a miss (lenny#200)', () async {
        // A find answering {"value": {}} used to throw StateError out of
        // `values.first`, escaping resolve and isPresent as a non-
        // NativeException.
        final NativeBackend b = _backends[name]!(
          _client(<http.Request>[], (http.Request r) async {
            if (!r.url.path.endsWith('/element')) return _json(null);
            return _json(<String, Object?>{});
          }),
        );
        await b.connect();
        const NativeSelector selector = NativeSelector(
          a11yId: 'passkey-prompt',
          label: 'Passkey',
          xpath: '//Sheet',
        );

        expect(await b.isPresent(selector), isFalse);
        expect(
          await b.resolve(selector, null, findTimeout: Duration.zero),
          isNull,
        );
        await b.close();
      });

      test('$name: a rect-only selector is an ArgumentError', () async {
        final NativeBackend b = _backends[name]!(
          _client(<http.Request>[], (_) async => _json(null)),
        );
        await b.connect();
        await expectLater(
          b.isPresent(const NativeSelector(rect: <int>[0, 0, 1, 1])),
          throwsArgumentError,
        );
        await b.close();
      });
    }

    test(
      'UiAutomator2Backend: a bare resource-id also tries web content',
      () async {
        final List<Object?> finds = <Object?>[];
        final NativeBackend b = _backends['UiAutomator2Backend']!(
          _client(<http.Request>[], (http.Request r) async {
            if (!r.url.path.endsWith('/element')) return _json(null);
            finds.add(jsonDecode(r.body)['value']);
            return _w3cError('no such element');
          }),
        );
        await b.connect();

        expect(
          await b.isPresent(const NativeSelector(resourceId: 'email')),
          isFalse,
        );
        expect(finds, <Object?>['email', "//*[@resource-id='email']"]);
        await b.close();
      },
    );
  });
}
