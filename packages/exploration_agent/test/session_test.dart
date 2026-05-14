import 'dart:async';

import 'package:exploration_agent/exploration_agent.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

class _FakeVmService extends VmService {
  _FakeVmService(this._handler)
      : super(
          const Stream<dynamic>.empty(),
          (_) {},
        );

  final Future<Response> Function(
    String method,
    String? isolateId,
    Map<String, dynamic>? args,
  ) _handler;

  bool disposed = false;

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) =>
      _handler(method, isolateId, args);

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

Response _resp(Map<String, dynamic> json) {
  final r = Response();
  r.json = json;
  return r;
}

VmServiceClient _clientWith(
  Future<Response> Function(
    String method,
    String? isolateId,
    Map<String, dynamic>? args,
  ) handler,
) {
  return VmServiceClient.forTest(_FakeVmService(handler), 'iso-test');
}

VmServiceClient _handshakeOnlyClient({
  String contractVersion = '1.0.0',
  List<Map<String, dynamic>> plugins = const <Map<String, dynamic>>[],
}) {
  return _clientWith((method, iso, args) async {
    if (method == 'ext.flutter.exploration.core.handshake') {
      return _resp(<String, dynamic>{
        'contractVersion': contractVersion,
        'plugins': plugins,
      });
    }
    return _resp(<String, dynamic>{});
  });
}

void main() {
  group('ExplorationSession.start', () {
    test('start performs handshake and emits SessionStarted', () async {
      final session = ExplorationSession.forTest(
        _handshakeOnlyClient(
          plugins: <Map<String, dynamic>>[
            <String, dynamic>{
              'namespace': 'router',
              'tools': <String>['router.go'],
            },
          ],
        ),
      );
      final firstEvent = session.progress.first;

      await session.start('login', const ExplorationConfig());

      expect(session.handshake.contractVersion, equals('1.0.0'));
      expect(session.handshake.plugins.first.namespace, equals('router'));

      final event = await firstEvent.timeout(const Duration(seconds: 1));
      expect(event, isA<SessionStarted>());
      expect((event as SessionStarted).goal, equals('login'));
    });

    test('double-start throws StateError', () async {
      final session = ExplorationSession.forTest(_handshakeOnlyClient());
      await session.start('first', const ExplorationConfig());

      await expectLater(
        session.start('second', const ExplorationConfig()),
        throwsA(isA<StateError>()),
      );
    });

    test('handshake getter throws before start()', () {
      final session = ExplorationSession.forTest(_handshakeOnlyClient());
      expect(() => session.handshake, throwsA(isA<StateError>()));
    });
  });

  group('ExplorationSession.observe / act', () {
    test('observe before start throws StateError', () async {
      final session = ExplorationSession.forTest(_handshakeOnlyClient());
      await expectLater(
        session.observe(),
        throwsA(isA<StateError>()),
      );
    });

    test('act before start throws StateError', () async {
      final session = ExplorationSession.forTest(_handshakeOnlyClient());
      await expectLater(
        session.act(const <String, dynamic>{
          'name': 'router.go',
          'args': <String, dynamic>{},
        }),
        throwsA(isA<StateError>()),
      );
    });

    test('observe delegates to the puller after start', () async {
      String? lastMethod;
      Map<String, dynamic>? lastArgs;
      final client = _clientWith((method, iso, args) async {
        lastMethod = method;
        lastArgs = args;
        if (method == 'ext.flutter.exploration.core.handshake') {
          return _resp(<String, dynamic>{
            'contractVersion': '1.0.0',
            'plugins': <Map<String, dynamic>>[],
          });
        }
        // get_stable_observation — return a minimally-valid bundle.
        return _resp(<String, dynamic>{
          'semantics': const <Object>[],
          'routes': const <String>[],
          'errors': const <Object>[],
          'stability': <String, dynamic>{
            'policy': 'action_relative',
            'terminated_by': 'idle',
            'duration_ms': 1,
            'framework_busy': <String, dynamic>{'anyBusy': false},
            'plugins_busy': const <Object>[],
          },
          'plugins': const <String, dynamic>{},
        });
      });
      final session = ExplorationSession.forTest(client);
      await session.start('goal', const ExplorationConfig());

      final Observation obs = await session.observe();
      expect(
        lastMethod,
        equals('ext.flutter.exploration.core.get_stable_observation'),
      );
      expect(lastArgs, containsPair('policy', 'action-relative'));
      expect(obs.core.routeStack, isEmpty);
      expect(obs.stability.terminatedBy, equals('idle'));
    });

    test('act delegates to the client after start', () async {
      String? lastMethod;
      Map<String, dynamic>? lastArgs;
      final client = _clientWith((method, iso, args) async {
        lastMethod = method;
        lastArgs = args;
        if (method == 'ext.flutter.exploration.core.handshake') {
          return _resp(<String, dynamic>{
            'contractVersion': '1.0.0',
            'plugins': <Map<String, dynamic>>[],
          });
        }
        return _resp(<String, dynamic>{'ok': true});
      });
      final session = ExplorationSession.forTest(client);
      await session.start('goal', const ExplorationConfig());

      final act = await session.act(const <String, dynamic>{
        'name': 'router.go',
        'args': <String, dynamic>{'route': '/home'},
      });
      expect(
        lastMethod,
        equals('ext.flutter.exploration.router.go'),
      );
      // Args go on the wire JSON-encoded per value so the binding's
      // `_tryDecode` round-trips them.
      expect(lastArgs?['route'], equals('"/home"'));
      expect(act, equals(<String, dynamic>{'ok': true}));
    });
  });

  group('ExplorationSession.disablePlugin', () {
    test('disablePlugin records and emits PluginAutoDisabled', () async {
      final session = ExplorationSession.forTest(_handshakeOnlyClient());
      final events = <SessionProgressEvent>[];
      final sub = session.progress.listen(events.add);

      session.disablePlugin('foo', 'timeout');

      // Allow stream microtask to flush.
      await Future<void>.delayed(Duration.zero);

      expect(session.disabledPlugins, contains('foo'));
      expect(events, hasLength(1));
      expect(events.first, isA<PluginAutoDisabled>());
      expect((events.first as PluginAutoDisabled).namespace, equals('foo'));
      expect((events.first as PluginAutoDisabled).reason, equals('timeout'));

      await sub.cancel();
    });

    test('disabledPlugins is unmodifiable', () {
      final session = ExplorationSession.forTest(_handshakeOnlyClient());
      session.disablePlugin('foo', 'r');
      expect(
        () => session.disabledPlugins.add('bar'),
        throwsUnsupportedError,
      );
    });
  });

  group('ExplorationSession.turnEvents', () {
    test('turnEvents broadcasts and closes', () async {
      final session = ExplorationSession.forTest(_handshakeOnlyClient());
      await session.start('g', const ExplorationConfig());
      final got = <TurnEvent>[];
      final sub = session.turnEvents.listen(got.add);

      session.emitTurnEvent(
        const TurnActionDecided(1, 'core.tap', <String, dynamic>{
          'node_id': 7,
        }),
      );
      session.emitTurnEvent(const TurnValidation(1, true, null));

      await Future<void>.delayed(Duration.zero);
      await session.end();
      await sub.cancel();

      expect(got, hasLength(2));
      expect(got.first, isA<TurnActionDecided>());
      expect((got.first as TurnActionDecided).toolName, equals('core.tap'));
      expect(got.last, isA<TurnValidation>());
    });

    test('emitTurnEvent after end is a no-op', () async {
      final session = ExplorationSession.forTest(_handshakeOnlyClient());
      await session.start('g', const ExplorationConfig());
      await session.end();

      // Must not throw.
      session.emitTurnEvent(const TurnComplete(0));
    });
  });

  group('ExplorationSession.end', () {
    test('end emits SessionEnded and disposes the client', () async {
      final fake = _FakeVmService(
        (method, iso, args) async => _resp(<String, dynamic>{
          'contractVersion': '1.0.0',
          'plugins': <Map<String, dynamic>>[],
        }),
      );
      final client = VmServiceClient.forTest(fake, 'iso-1');
      final session = ExplorationSession.forTest(client);
      final events = <SessionProgressEvent>[];
      final sub = session.progress.listen(events.add);

      await session.start('g', const ExplorationConfig());
      await session.end();

      expect(events.whereType<SessionStarted>(), hasLength(1));
      expect(events.whereType<SessionEnded>(), hasLength(1));
      expect(fake.disposed, isTrue);

      await sub.cancel();
    });

    test('end is a no-op when start never ran', () async {
      final fake = _FakeVmService(
        (method, iso, args) async => _resp(<String, dynamic>{}),
      );
      final client = VmServiceClient.forTest(fake, 'iso-1');
      final session = ExplorationSession.forTest(client);
      final events = <SessionProgressEvent>[];
      final sub = session.progress.listen(events.add);

      await session.end();
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
      expect(fake.disposed, isTrue);
      await sub.cancel();
    });
  });
}
