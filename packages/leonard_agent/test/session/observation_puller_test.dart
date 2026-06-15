import 'package:leonard_agent/leonard_agent.dart';
import 'package:leonard_agent/src/session/observation_puller.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

class _FakeVmService extends VmService {
  _FakeVmService(this._handler) : super(const Stream<dynamic>.empty(), (_) {});

  final Future<Response> Function(
    String method,
    String? isolateId,
    Map<String, dynamic>? args,
  )
  _handler;

  int callCount = 0;
  String? lastMethod;
  Map<String, dynamic>? lastArgs;

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) {
    callCount++;
    lastMethod = method;
    lastArgs = args;
    return _handler(method, isolateId, args);
  }

  @override
  Future<void> dispose() async {}
}

Response _resp(Map<String, dynamic> json) {
  final Response r = Response();
  r.json = json;
  return r;
}

Map<String, dynamic> _bundle() => <String, dynamic>{
  'semantics': <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 1,
      'role': 'button',
      'rect': <int>[0, 0, 10, 10],
    },
  ],
  'routes': <String>['/home'],
  'errors': const <Object>[],
  'stability': <String, dynamic>{
    'policy': 'action_relative',
    'terminated_by': 'idle',
    'duration_ms': 33,
    'framework_busy': <String, dynamic>{'anyBusy': false},
    'extensions_busy': const <Object>[],
  },
  'extensions': <String, dynamic>{
    'router': <String, dynamic>{'path': '/home'},
  },
};

void main() {
  group('ObservationPuller.pull', () {
    test(
      'issues one call to get_stable_observation with the policy arg',
      () async {
        final _FakeVmService fake = _FakeVmService(
          (String method, String? iso, Map<String, dynamic>? args) async =>
              _resp(_bundle()),
        );
        final VmServiceClient client = VmServiceClient.forTest(fake, 'iso-1');
        final ObservationPuller puller = ObservationPuller(client);

        final Observation obs = await puller.pull();

        expect(fake.callCount, equals(1));
        expect(
          fake.lastMethod,
          equals('ext.exploration.core.get_stable_observation'),
        );
        expect(fake.lastArgs, containsPair('policy', 'action-relative'));
        expect(obs.core.nodes.keys, equals(<int>{1}));
        expect(obs.core.routeStack, equals(<String>['/home']));
        expect(
          obs.extensions['router']!.data,
          equals(<String, dynamic>{'path': '/home'}),
        );
        expect(obs.stability.terminatedBy, equals('idle'));
      },
    );

    test('threads non-default policy onto the wire', () async {
      final _FakeVmService fake = _FakeVmService(
        (_, __, ___) async => _resp(_bundle()),
      );
      final VmServiceClient client = VmServiceClient.forTest(fake, 'iso-1');
      final ObservationPuller puller = ObservationPuller(client);

      await puller.pull(policy: StabilityPolicy.boundedStability);
      expect(fake.lastArgs, containsPair('policy', 'bounded-stability'));

      await puller.pull(policy: StabilityPolicy.quietFrame);
      expect(fake.lastArgs, containsPair('policy', 'quiet-frame'));
    });

    test(
      'StabilityPolicy.wireName matches the binding kebab-case contract',
      () {
        expect(
          StabilityPolicy.actionRelative.wireName,
          equals('action-relative'),
        );
        expect(StabilityPolicy.quietFrame.wireName, equals('quiet-frame'));
        expect(
          StabilityPolicy.boundedStability.wireName,
          equals('bounded-stability'),
        );
      },
    );

    test(
      'unwraps {type, value} envelope when the binding wraps the bundle',
      () async {
        final _FakeVmService fake = _FakeVmService(
          (_, __, ___) async => _resp(<String, dynamic>{
            'type': 'Observation',
            'value': _bundle(),
          }),
        );
        final VmServiceClient client = VmServiceClient.forTest(fake, 'iso-1');
        final ObservationPuller puller = ObservationPuller(client);

        final Observation obs = await puller.pull();
        expect(obs.core.nodes.keys, equals(<int>{1}));
        expect(obs.extensions.keys, equals(<String>{'router'}));
      },
    );
  });
}
