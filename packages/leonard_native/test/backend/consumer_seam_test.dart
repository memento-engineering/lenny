/// UNIT (NOT e2e): the seam a consumer drives directly — `alertText`
/// (lenny#180), `activateApp` (lenny#182) and `resolve`'s `findTimeout`
/// (lenny#183) — on each REAL Appium backend over a MOCKED `http.Client`.
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
}
