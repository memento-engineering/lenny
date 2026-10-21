/// UNIT (NOT e2e): transport hygiene on each REAL Appium backend over a
/// MOCKED `http.Client` — credentials never leave in an error (lenny#186), a
/// failed connect releases the session it opened (lenny#185), the factory
/// forwards a caller's client (lenny#187), and close closes only a client the
/// backend created (lenny#198).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:leonard_native/leonard_native.dart';
import 'package:leonard_native/src/appium_endpoint.dart';
import 'package:test/test.dart';

final Uri _grid = Uri.parse('https://alice:s3cr3tKey@hub.example.com/wd/hub');

http.Response _json(Object? value, {int status = 200}) => http.Response(
  jsonEncode(<String, Object?>{'value': value}),
  status,
  headers: const <String, String>{'content-type': 'application/json'},
);

typedef _Make = NativeBackend Function(http.Client client);

final Map<String, _Make> _backends = <String, _Make>{
  'XcuiTestBackend': (http.Client c) =>
      XcuiTestBackend(server: _grid, udid: 'U', app: 'lt://APP', client: c),
  'UiAutomator2Backend': (http.Client c) =>
      UiAutomator2Backend(server: _grid, udid: 'U', app: 'lt://APP', client: c),
  'Mac2Backend': (http.Client c) =>
      Mac2Backend(server: _grid, bundleId: 'engineering.memento', client: c),
};

/// A caller-owned client that, like `IOClient`, refuses every request once
/// closed, so a backend that closes it is caught by the next request.
final class _CallerClient extends http.BaseClient {
  _CallerClient(MockClientHandler handler) : _inner = MockClient(handler);

  final MockClient _inner;

  /// Whether [close] has been called.
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (closed) {
      throw http.ClientException('Client is already closed.', request.url);
    }
    return _inner.send(request);
  }

  @override
  void close() {
    closed = true;
    _inner.close();
  }
}

Matcher _redactedTransportError() => isA<NativeException>()
    .having((NativeException e) => e.code, 'code', 'transport error')
    .having(
      (NativeException e) => e.message,
      'message',
      allOf(contains('https://***@hub.example.com'), isNot(contains('s3cr3t'))),
    );

void main() {
  group('redactCredentials', () {
    test('masks userinfo and leaves credential-free URLs alone', () {
      expect(
        redactCredentials(
          'POST https://alice:key@hub.example.com/wd/hub/session failed; '
          'retry http://127.0.0.1:4723/session',
        ),
        'POST https://***@hub.example.com/wd/hub/session failed; '
        'retry http://127.0.0.1:4723/session',
      );
    });
  });

  for (final MapEntry<String, _Make> backend in _backends.entries) {
    group(backend.key, () {
      test('a transport failure is a redacted NativeException', () async {
        final NativeBackend b = backend.value(
          MockClient(
            (http.Request request) async =>
                throw http.ClientException('Connection reset', request.url),
          ),
        );

        await expectLater(b.connect(), throwsA(_redactedTransportError()));
      });

      test('a W3C error or body quoting the URL is redacted', () async {
        final NativeBackend b = backend.value(
          MockClient(
            (http.Request request) async =>
                request.url.path.endsWith('/session')
                ? _json(<String, Object?>{
                    'error': 'session not created',
                    'message': 'grid at ${request.url} refused',
                  }, status: 500)
                : _json(null),
          ),
        );

        await expectLater(
          b.connect(),
          throwsA(
            isA<NativeException>().having(
              (NativeException e) => e.message,
              'message',
              allOf(contains('***@'), isNot(contains('s3cr3t'))),
            ),
          ),
        );
      });

      test('resolve fails at once on a dead transport', () async {
        int finds = 0;
        final NativeBackend b = backend.value(
          MockClient((http.Request request) async {
            if (request.url.path.endsWith('/wd/hub/session')) {
              return _json(<String, Object?>{'sessionId': 's1'});
            }
            if (request.url.path.endsWith('/element')) {
              finds++;
              throw http.ClientException('Connection refused', request.url);
            }
            return _json(null);
          }),
        );
        await b.connect();

        await expectLater(
          b.resolve(const NativeSelector(a11yId: 'x'), null),
          throwsA(_redactedTransportError()),
        );
        expect(finds, 1, reason: 'a dead transport is not a miss to retry');
      });
    });
  }

  group('a failed connect releases the session it opened', () {
    MockClient client(
      List<String> log, {
      Object? appState = 1,
      bool failContext = false,
      bool probeTransportFails = false,
    }) => MockClient((http.Request request) async {
      final String path = request.url.path;
      log.add('${request.method} $path');
      if (path == '/session') {
        return _json(<String, Object?>{'sessionId': 's${log.length}'});
      }
      if (path.endsWith('/context') && failContext) {
        return _json(<String, Object?>{
          'error': 'unknown error',
          'message': 'context switch failed',
        }, status: 500);
      }
      if (path.endsWith('/execute/sync')) {
        if (probeTransportFails) {
          throw http.ClientException('Connection reset', request.url);
        }
        return _json(appState);
      }
      return _json(null);
    });

    final Map<String, NativeAttach> attaches = <String, NativeAttach>{
      'XcuiTestBackend': XcuiTestBackend.attach,
      'UiAutomator2Backend': UiAutomator2Backend.attach,
    };
    for (final MapEntry<String, NativeAttach> attach in attaches.entries) {
      test('${attach.key}: the attach check fails', () async {
        final List<String> log = <String>[];
        final NativeBackend b = attach.value(
          udid: 'U',
          appId: 'engineering.memento.Runner',
          client: client(log),
        );

        await expectLater(b.connect(), throwsA(isA<NativeException>()));

        expect(log.last, 'DELETE /session/s1');
        // The state is cleared, so a retried connect opens a new session.
        await expectLater(b.connect(), throwsA(isA<NativeException>()));
        expect(log.where((String l) => l == 'POST /session'), hasLength(2));
      });

      test('${attach.key}: a dead transport on the probe fails', () async {
        final List<String> log = <String>[];
        final NativeBackend b = attach.value(
          udid: 'U',
          appId: 'engineering.memento.Runner',
          client: client(log, probeTransportFails: true),
        );

        await expectLater(
          b.connect(),
          throwsA(
            isA<NativeException>().having(
              (NativeException e) => e.code,
              'code',
              NativeException.transportErrorCode,
            ),
          ),
        );
        expect(log.last, 'DELETE /session/s1');
      });
    }

    test('XcuiTestBackend: the context switch fails', () async {
      final List<String> log = <String>[];
      final NativeBackend b = XcuiTestBackend(
        udid: 'U',
        app: '/x/Runner.app',
        client: client(log, failContext: true),
      );

      await expectLater(b.connect(), throwsA(isA<NativeException>()));
      expect(log.last, 'DELETE /session/s1');
    });
  });

  group('close closes only the client the backend created (lenny#198)', () {
    for (final MapEntry<String, _Make> backend in _backends.entries) {
      test('${backend.key}: a caller-supplied client stays open', () async {
        final List<String> log = <String>[];
        final _CallerClient client = _CallerClient((
          http.Request request,
        ) async {
          log.add('${request.method} ${request.url.path}');
          return request.url.path.endsWith('/wd/hub/session')
              ? _json(<String, Object?>{'sessionId': 's1'})
              : _json(null);
        });
        final NativeBackend first = backend.value(client);
        await first.connect();

        await first.close();

        expect(client.closed, isFalse);
        expect(log.last, 'DELETE /wd/hub/session/s1');
        // The caller's client still serves the next backend.
        final NativeBackend second = backend.value(client);
        await second.connect();
        await second.close();
        expect(client.closed, isFalse);
      });

      test('${backend.key}: close after a failed connect leaves the client '
          'usable', () async {
        int sessions = 0;
        final _CallerClient client = _CallerClient((
          http.Request request,
        ) async {
          if (request.url.path.endsWith('/wd/hub/session')) {
            sessions++;
            return sessions == 1
                ? _json(<String, Object?>{
                    'error': 'session not created',
                    'message': 'no device free',
                  }, status: 500)
                : _json(<String, Object?>{'sessionId': 's$sessions'});
          }
          return _json(null);
        });
        final NativeBackend b = backend.value(client);
        await expectLater(b.connect(), throwsA(isA<NativeException>()));

        await b.close();

        expect(client.closed, isFalse);
        await b.connect();
        expect(sessions, 2);
        await b.close();
        expect(client.closed, isFalse);
      });
    }

    // A backend built without a client owns the one it creates. No request is
    // sent before the close, and a closed `IOClient` refuses the next one
    // before touching the network, so this needs no server.
    final Uri nowhere = Uri.parse('http://127.0.0.1:9');
    final Map<String, NativeBackend Function()> selfOwned =
        <String, NativeBackend Function()>{
          'XcuiTestBackend': () =>
              XcuiTestBackend(server: nowhere, udid: 'U', app: '/x/R.app'),
          'UiAutomator2Backend': () =>
              UiAutomator2Backend(server: nowhere, udid: 'U', app: '/x/a.apk'),
          'Mac2Backend': () =>
              Mac2Backend(server: nowhere, bundleId: 'engineering.memento'),
        };
    for (final MapEntry<String, NativeBackend Function()> backend
        in selfOwned.entries) {
      test('${backend.key}: a client it created is closed', () async {
        final NativeBackend b = backend.value();

        await b.close();

        await expectLater(
          b.connect(),
          throwsA(
            isA<NativeException>()
                .having(
                  (NativeException e) => e.code,
                  'code',
                  NativeException.transportErrorCode,
                )
                .having(
                  (NativeException e) => e.message,
                  'message',
                  contains('Client is already closed'),
                ),
          ),
        );
      });
    }
  });

  group('backendForPlatform forwards client', () {
    for (final (String platform, String? app, String? appId)
        in <(String, String?, String?)>[
          ('ios', '/x/Runner.app', null),
          ('ios', null, 'engineering.memento.Runner'),
          ('android', '/x/app.apk', null),
          ('android', null, 'engineering.memento.runner'),
          ('darwin', null, 'engineering.memento.Mac'),
        ]) {
      test('$platform ${app == null ? 'attach' : 'launch'}', () async {
        final List<String> paths = <String>[];
        final NativeBackend b = backendForPlatform(
          platform: platform,
          udid: 'U',
          app: app,
          appId: appId,
          client: MockClient((http.Request request) async {
            paths.add(request.url.path);
            return request.url.path == '/session'
                ? _json(<String, Object?>{'sessionId': 's1'})
                : _json(4);
          }),
        );

        await b.connect();
        expect(paths.first, '/session');
        await b.close();
      });
    }
  });
}
