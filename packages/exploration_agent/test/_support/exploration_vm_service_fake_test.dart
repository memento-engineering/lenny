// packages/exploration_agent/test/_support/exploration_vm_service_fake_test.dart
/// Smoke tests for [ExplorationVmServiceFake] (lenny-5o8).
///
/// Confirms the three dispatch layers (handshake, observation, handler
/// table), the `calls` recording, and end-to-end integration with
/// [ExplorationSession] + [ObservationPuller] — all under `dart test`
/// with no Flutter dependency.
library;

import 'package:exploration_agent/exploration_agent.dart'
    show ExplorationConfig, ExplorationSession;
import 'package:exploration_agent/src/session/observation_puller.dart'
    show StabilityPolicy;
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import 'exploration_vm_service_fake.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Map<String, dynamic> _handshake({
  String version = '1',
  List<dynamic> plugins = const <dynamic>[],
}) =>
    <String, dynamic>{'protocolVersion': version, 'plugins': plugins};

Map<String, dynamic> _bundle({
  List<String> routes = const <String>['login'],
  List<Map<String, dynamic>> semantics = const <Map<String, dynamic>>[],
}) =>
    <String, dynamic>{
      'semantics': semantics,
      'routes': routes,
      'errors': const <dynamic>[],
      'stability': <String, dynamic>{
        'policy': 'action_relative',
        'reason': 'idle',
      },
      'plugins': const <String, dynamic>{},
    };

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ExplorationVmServiceFake — dispatch', () {
    test('handshake returns handshakeResponse verbatim', () async {
      final fake = ExplorationVmServiceFake(
        handshakeResponse: _handshake(version: '2'),
      );
      final r = await fake.callServiceExtension(
        'ext.flutter.exploration.core.handshake',
      );
      expect(r.json!['protocolVersion'], '2');
      expect(fake.calls, hasLength(1));
      expect(fake.calls.single.method,
          'ext.flutter.exploration.core.handshake');
    });

    test('observation returns {type: Observation, value: bundle}', () async {
      final fake = ExplorationVmServiceFake(
        handshakeResponse: _handshake(),
        observationBundle: _bundle(routes: <String>['/home']),
      );
      final r = await fake.callServiceExtension(
        'ext.flutter.exploration.core.get_stable_observation',
        args: <String, dynamic>{'policy': 'action-relative'},
      );
      expect(r.json!['type'], 'Observation');
      final Map<String, dynamic> value =
          (r.json!['value'] as Map).cast<String, dynamic>();
      expect(value['routes'], <String>['/home']);
    });

    test('observation throws RPCError(-32601) when bundle is null', () async {
      final fake = ExplorationVmServiceFake(
        handshakeResponse: _handshake(),
        // no observationBundle
      );
      await expectLater(
        fake.callServiceExtension(
          'ext.flutter.exploration.core.get_stable_observation',
        ),
        throwsA(
          isA<RPCError>().having((e) => e.code, 'code', -32601),
        ),
      );
    });

    test('handler table routes arbitrary extension', () async {
      final fake = ExplorationVmServiceFake(
        handshakeResponse: _handshake(),
        handlers: <String,
            Future<Map<String, dynamic>> Function(Map<String, dynamic>?)>{
          'ext.flutter.exploration.router.navigate': (args) async =>
              <String, dynamic>{'ok': true, 'value': args?['route_name']},
        },
      );
      final r = await fake.callServiceExtension(
        'ext.flutter.exploration.router.navigate',
        args: <String, dynamic>{'route_name': '"settings"'},
      );
      expect(r.json!['ok'], true);
      expect(r.json!['value'], '"settings"');
    });

    test('unknown method throws RPCError(-32601)', () async {
      final fake = ExplorationVmServiceFake(handshakeResponse: _handshake());
      await expectLater(
        fake.callServiceExtension('ext.flutter.exploration.core.unknown'),
        throwsA(
          isA<RPCError>().having((e) => e.code, 'code', -32601),
        ),
      );
    });

    test('calls list records every invocation in order', () async {
      final fake = ExplorationVmServiceFake(
        handshakeResponse: _handshake(),
        observationBundle: _bundle(),
      );
      await fake.callServiceExtension(
          'ext.flutter.exploration.core.handshake');
      await fake.callServiceExtension(
        'ext.flutter.exploration.core.get_stable_observation',
        isolateId: 'iso-1',
        args: <String, dynamic>{'policy': 'action-relative'},
      );
      expect(fake.calls, hasLength(2));
      expect(fake.calls[0].method, 'ext.flutter.exploration.core.handshake');
      expect(fake.calls[1].isolateId, 'iso-1');
      expect(fake.calls[1].args?['policy'], 'action-relative');
    });
  });

  group('ExplorationVmServiceFake — ExplorationSession integration', () {
    test('session.start() succeeds and handshake is populated', () async {
      final fake = ExplorationVmServiceFake(
        handshakeResponse: _handshake(
          version: '1',
          plugins: <dynamic>[
            <String, dynamic>{
              'namespace': 'router',
              'tools': <String>['navigate'],
            },
          ],
        ),
      );
      final session = ExplorationSession.fromVmService(fake, 'isolate-0');
      await session.start('test goal', const ExplorationConfig());
      expect(session.handshake.contractVersion, '1');
      expect(session.handshake.plugins, hasLength(1));
      expect(session.handshake.plugins.first.namespace, 'router');
      await session.end();
    });

    test('session.pullObservation() decodes bundle into typed Observation',
        () async {
      final fake = ExplorationVmServiceFake(
        handshakeResponse: _handshake(),
        observationBundle: _bundle(
          routes: <String>['login'],
          semantics: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 1,
              'role': 'textfield',
              'label': 'Email',
              'rect': <int>[0, 0, 100, 40],
            },
            <String, dynamic>{
              'id': 2,
              'role': 'button',
              'label': 'Sign in',
              'rect': <int>[0, 50, 100, 90],
            },
          ],
        ),
      );
      final session = ExplorationSession.fromVmService(fake, 'isolate-0');
      await session.start('test goal', const ExplorationConfig());
      try {
        final obs = await session.pullObservation(
          policy: StabilityPolicy.actionRelative,
        );
        expect(obs.core.routeStack, <String>['login']);
        expect(obs.core.nodes.length, 2);
        expect(obs.core.nodes.keys.toSet(), <int>{1, 2});
      } finally {
        await session.end();
      }
    });
  });
}
