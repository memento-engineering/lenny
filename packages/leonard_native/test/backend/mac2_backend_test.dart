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

void main() {
  group('Mac2Backend session lifecycle', () {
    test(
      'sends attach capabilities, validates idempotent calls, and closes',
      () async {
        final List<http.Request> requests = <http.Request>[];
        final MockClient client = MockClient((http.Request request) async {
          requests.add(request);
          if (request.url.path == '/session') {
            return _json(<String, Object?>{'sessionId': 'mac-session'});
          }
          return _json(null);
        });
        final Mac2Backend backend = Mac2Backend(
          server: Uri.parse('http://127.0.0.1:4999'),
          bundleId: 'com.nicospencer.butaneHarness',
          client: client,
        );

        await backend.connect(
          extraCapabilities: const <String, Object?>{
            'appium:showServerLogs': true,
          },
        );
        expect(requests, hasLength(1));
        final Map<String, Object?> body =
            jsonDecode(requests.single.body) as Map<String, Object?>;
        expect(body, <String, Object?>{
          'capabilities': <String, Object?>{
            'alwaysMatch': <String, Object?>{
              'platformName': 'mac',
              'appium:automationName': 'Mac2',
              'appium:bundleId': 'com.nicospencer.butaneHarness',
              'appium:noReset': true,
              'appium:skipAppKill': true,
              'appium:showServerLogs': true,
            },
            'firstMatch': <Object?>[<String, Object?>{}],
          },
        });

        await backend.connect();
        expect(requests, hasLength(1));
        await expectLater(
          backend.connect(
            extraCapabilities: const <String, Object?>{
              'appium:skipAppKill': false,
            },
          ),
          throwsA(isA<ArgumentError>()),
        );
        expect(requests, hasLength(1));

        await backend.close();
        expect(requests, hasLength(2));
        expect(requests.last.method, 'DELETE');
        expect(requests.last.url.path, '/session/mac-session');
      },
    );

    test('accepts a legacy top-level session id envelope', () async {
      final Mac2Backend backend = Mac2Backend(
        bundleId: 'com.example.Runner',
        client: MockClient((http.Request request) async {
          if (request.url.path == '/session') {
            return http.Response(
              jsonEncode(<String, Object?>{
                'sessionId': 'legacy-session',
                'value': <String, Object?>{},
              }),
              200,
            );
          }
          return _json(null);
        }),
      );
      await backend.connect();
      await backend.press('return');
      await backend.close();
    });

    test('missing session id is a NativeException', () async {
      final Mac2Backend backend = Mac2Backend(
        bundleId: 'com.example.Runner',
        client: MockClient((http.Request request) async => _json(null)),
      );
      await expectLater(backend.connect(), throwsA(isA<NativeException>()));
      await backend.close();
    });
  });

  group('Mac2Backend transport hardening', () {
    test('non-JSON response is a NativeException', () async {
      final Mac2Backend backend = Mac2Backend(
        bundleId: 'com.example.Runner',
        client: MockClient(
          (http.Request request) async =>
              http.Response('<html>nope</html>', 500),
        ),
      );
      await expectLater(
        backend.connect(),
        throwsA(
          isA<NativeException>().having(
            (NativeException error) => error.message,
            'message',
            contains('non-JSON response: HTTP 500'),
          ),
        ),
      );
      await backend.close();
    });

    test('W3C error envelope preserves the structured code', () async {
      final Mac2Backend backend = Mac2Backend(
        bundleId: 'com.example.Runner',
        client: MockClient(
          (http.Request request) async => _json(<String, Object?>{
            'error': 'session not created',
            'message': 'mac2 unavailable',
          }, status: 500),
        ),
      );
      await expectLater(
        backend.connect(),
        throwsA(
          isA<NativeException>()
              .having(
                (NativeException error) => error.code,
                'code',
                'session not created',
              )
              .having(
                (NativeException error) => error.message,
                'message',
                contains('mac2 unavailable'),
              ),
        ),
      );
      await backend.close();
    });

    test('HTTP failure without a W3C error is a NativeException', () async {
      final Mac2Backend backend = Mac2Backend(
        bundleId: 'com.example.Runner',
        client: MockClient(
          (http.Request request) async => _json(null, status: 503),
        ),
      );
      await expectLater(
        backend.connect(),
        throwsA(
          isA<NativeException>().having(
            (NativeException error) => error.message,
            'message',
            contains('HTTP 503'),
          ),
        ),
      );
      await backend.close();
    });
  });

  test(
    'snapshot and watch parse darwin source through the poll loop',
    () async {
      var sourceRequests = 0;
      final Mac2Backend backend = Mac2Backend(
        bundleId: 'com.example.Runner',
        pollInterval: const Duration(milliseconds: 1),
        client: MockClient((http.Request request) async {
          if (request.url.path == '/session') {
            return _json(<String, Object?>{'sessionId': 's1'});
          }
          if (request.url.path == '/session/s1/source') {
            sourceRequests++;
            return _json('''
<AppiumAUT>
  <XCUIElementTypeButton identifier="central" label="Central"
    x="10" y="20" width="100" height="40"/>
</AppiumAUT>''');
          }
          return _json(null);
        }),
      );
      await backend.connect();

      final NativeSnapshot direct = await backend.snapshot();
      expect(direct.platform, 'darwin');
      expect(direct.nodes.single.label, 'Central');
      final NativeSnapshot watched = await backend.watch().first;
      expect(watched.nodes.single.a11yId, 'central');
      expect(sourceRequests, 2);
      await backend.close();
    },
  );

  test(
    'resolution skips resource id and follows the four macOS tiers',
    () async {
      final List<Map<String, Object?>> finds = <Map<String, Object?>>[];
      final Mac2Backend backend = Mac2Backend(
        bundleId: 'com.example.Runner',
        client: MockClient((http.Request request) async {
          if (request.url.path == '/session') {
            return _json(<String, Object?>{'sessionId': 's1'});
          }
          if (request.url.path == '/session/s1/element') {
            final Map<String, Object?> body = (jsonDecode(request.body) as Map)
                .cast<String, Object?>();
            finds.add(body);
            return _json(<String, Object?>{
              'element-6066-11e4-a52e-4f735466cecf':
                  'E-${body['using']}-${body['value']}',
            });
          }
          return _json(null);
        }),
      );
      await backend.connect();
      const NativeSnapshot cached = NativeSnapshot(
        platform: 'darwin',
        nodes: <NativeNode>[
          NativeNode(
            id: 1,
            role: 'button',
            label: 'Central',
            rect: <int>[10, 20, 110, 60],
            a11yId: 'central',
            xpath: "//XCUIElementTypeButton[@identifier='central']",
          ),
          NativeNode(
            id: 2,
            role: 'button',
            label: 'Anonymous',
            rect: <int>[50, 80, 150, 120],
            xpath: '(//XCUIElementTypeButton)[2]',
          ),
        ],
      );

      final NativeTarget? a11y = await backend.resolve(
        const NativeSelector(
          resourceId: 'android:id/button1',
          a11yId: 'central',
        ),
        cached,
      );
      final NativeTarget? label = await backend.resolve(
        const NativeSelector(label: 'Anonymous'),
        cached,
      );
      final NativeTarget? xpath = await backend.resolve(
        const NativeSelector(xpath: '//XCUIElementTypeSlider'),
        cached,
      );
      final NativeTarget? rect = await backend.resolve(
        const NativeSelector(rect: <int>[10, 20, 30, 40]),
        cached,
      );

      expect(a11y?.via, 'a11y-id');
      expect(label?.via, 'label');
      expect(xpath?.via, 'xpath');
      expect(rect?.via, 'rect-center');
      expect(rect?.point, (x: 20, y: 30));
      expect(finds, <Map<String, Object?>>[
        <String, Object?>{'using': 'accessibility id', 'value': 'central'},
        <String, Object?>{
          'using': 'xpath',
          'value': '(//XCUIElementTypeButton)[2]',
        },
        <String, Object?>{'using': 'xpath', 'value': '//XCUIElementTypeSlider'},
      ]);
      await backend.close();
    },
  );

  test('tap, swipe, and Return use mac2-compatible action payloads', () async {
    final List<http.Request> requests = <http.Request>[];
    final Mac2Backend backend = Mac2Backend(
      bundleId: 'com.example.Runner',
      client: MockClient((http.Request request) async {
        requests.add(request);
        if (request.url.path == '/session') {
          return _json(<String, Object?>{'sessionId': 's1'});
        }
        return _json(null);
      }),
    );
    await backend.connect();
    await backend.tap(
      const NativeTarget(elementId: 'E1', via: 'accessibility-id'),
    );
    await backend.tap(
      const NativeTarget(point: (x: 40, y: 50), via: 'rect-center'),
    );
    await backend.swipe(
      const NativeSwipe(
        fromX: 40,
        fromY: 50,
        toX: 65,
        toY: 55,
        durationMs: 175,
      ),
    );
    await backend.press('return');

    expect(requests[1].url.path, '/session/s1/element/E1/click');
    final List<http.Request> actions = requests
        .where((http.Request request) => request.url.path.endsWith('/actions'))
        .toList();
    expect(actions, hasLength(2));
    for (final http.Request request in actions) {
      final Map<String, Object?> body =
          jsonDecode(request.body) as Map<String, Object?>;
      final Map<String, Object?> pointer =
          (body['actions']! as List<Object?>).single! as Map<String, Object?>;
      expect(
        (pointer['parameters']! as Map<String, Object?>)['pointerType'],
        'mouse',
      );
    }
    final Map<String, Object?> tapBody =
        jsonDecode(actions.first.body) as Map<String, Object?>;
    final Map<String, Object?> tapPointer =
        (tapBody['actions']! as List<Object?>).single! as Map<String, Object?>;
    expect((tapPointer['actions']! as List<Object?>).first, <String, Object?>{
      'type': 'pointerMove',
      'duration': 0,
      'x': 40,
      'y': 50,
    });
    final Map<String, Object?> swipeBody =
        jsonDecode(actions.last.body) as Map<String, Object?>;
    final Map<String, Object?> swipePointer =
        (swipeBody['actions']! as List<Object?>).single!
            as Map<String, Object?>;
    expect((swipePointer['actions']! as List<Object?>)[2], <String, Object?>{
      'type': 'pointerMove',
      'duration': 175,
      'x': 65,
      'y': 55,
    });

    final http.Request execute = requests.singleWhere(
      (http.Request request) => request.url.path.endsWith('/execute/sync'),
    );
    expect(jsonDecode(execute.body), <String, Object?>{
      'script': 'macos: keys',
      'args': <Object?>[
        <String, Object?>{
          'keys': <String>['XCUIKeyboardKeyReturn'],
        },
      ],
    });
    await backend.close();
  });

  test('enterText reads mac2 value and derives masking from amType', () async {
    final List<String> hits = <String>[];
    final List<Map<String, Object?>> valueBodies = <Map<String, Object?>>[];
    final Mac2Backend backend = Mac2Backend(
      bundleId: 'com.example.Runner',
      client: MockClient((http.Request request) async {
        hits.add('${request.method} ${request.url.path}');
        if (request.url.path == '/session') {
          return _json(<String, Object?>{'sessionId': 's1'});
        }
        if (request.url.path.endsWith('/value') && request.method == 'POST') {
          valueBodies.add(
            (jsonDecode(request.body) as Map).cast<String, Object?>(),
          );
          return _json(null);
        }
        if (request.url.path.endsWith('/attribute/amType')) {
          return _json('XCUIElementTypeSecureTextField');
        }
        if (request.url.path.endsWith('/attribute/value')) {
          return _json('••••••');
        }
        return _json(null);
      }),
    );
    await backend.connect();
    final ({String readback, bool masked}) result = await backend.enterText(
      const NativeTarget(elementId: 'secure', via: 'a11y-id'),
      'secret',
    );

    expect(result, (readback: '••••••', masked: true));
    expect(valueBodies, <Map<String, Object?>>[
      <String, Object?>{'text': 'secret'},
    ]);
    expect(hits, contains('GET /session/s1/element/secure/attribute/amType'));
    expect(hits, contains('GET /session/s1/element/secure/attribute/value'));
    expect(hits.where((String hit) => hit.contains('keyboard')), isEmpty);
    expect(hits.where((String hit) => hit.endsWith('/back')), isEmpty);
    await backend.close();
  });

  test('unknown and permission keys fail without transport I/O', () async {
    final List<String> hits = <String>[];
    final Mac2Backend backend = Mac2Backend(
      bundleId: 'com.example.Runner',
      client: MockClient((http.Request request) async {
        hits.add('${request.method} ${request.url.path}');
        if (request.url.path == '/session') {
          return _json(<String, Object?>{'sessionId': 's1'});
        }
        return _json(null);
      }),
    );
    await backend.connect();
    final List<String> before = List<String>.of(hits);
    for (final String key in <String>[
      'back',
      'permission_allow',
      'permission_deny',
      'consent_accept',
    ]) {
      await expectLater(backend.press(key), throwsA(isA<NativeException>()));
    }
    expect(hits, before);
    await backend.close();
  });
}
