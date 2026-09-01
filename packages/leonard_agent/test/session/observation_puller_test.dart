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

Map<String, dynamic> _envelope() => <String, dynamic>{
  'type': 'Observation',
  'value': _bundle(),
};

void main() {
  group('ObservationPuller.pull', () {
    test(
      'issues one call to get_stable_observation with the policy arg',
      () async {
        final _FakeVmService fake = _FakeVmService(
          (String method, String? iso, Map<String, dynamic>? args) async =>
              _resp(_envelope()),
        );
        final VmServiceClient client = VmServiceClient.forTest(fake, 'iso-1');
        final ObservationPuller puller = ObservationPuller(client);

        final Observation obs = await puller.pull();

        expect(fake.callCount, equals(1));
        expect(
          fake.lastMethod,
          equals('ext.leonard.core.get_stable_observation'),
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
        (_, __, ___) async => _resp(_envelope()),
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
          (_, __, ___) async => _resp(_envelope()),
        );
        final VmServiceClient client = VmServiceClient.forTest(fake, 'iso-1');
        final ObservationPuller puller = ObservationPuller(client);

        final Observation obs = await puller.pull();
        expect(obs.core.nodes.keys, equals(<int>{1}));
        expect(obs.extensions.keys, equals(<String>{'router'}));
      },
    );

    test('accepts a DWDS response type when value contains core', () async {
      final _FakeVmService fake = _FakeVmService(
        (_, __, ___) async =>
            _resp(<String, dynamic>{'type': 'Response', 'value': _bundle()}),
      );
      final ObservationPuller puller = ObservationPuller(
        VmServiceClient.forTest(fake, 'iso-1'),
      );

      final Observation obs = await puller.pull();

      expect(obs.core.nodes.keys, equals(<int>{1}));
      expect(obs.extensions.keys, equals(<String>{'router'}));
    });

    test('accepts a tools-only host envelope', () async {
      final _FakeVmService fake = _FakeVmService(
        (_, __, ___) async => _resp(<String, dynamic>{
          'type': 'Observation',
          'value': <String, dynamic>{
            'extensions': <String, dynamic>{
              'tmux': <String, dynamic>{'pane': 'main'},
            },
          },
        }),
      );
      final ObservationPuller puller = ObservationPuller(
        VmServiceClient.forTest(fake, 'iso-1'),
      );

      final Observation obs = await puller.pull();

      expect(obs.core.nodes, isEmpty);
      expect(obs.extensions['tmux']?.data, <String, dynamic>{'pane': 'main'});
    });

    test('sends an optional core budget as a string', () async {
      final _FakeVmService fake = _FakeVmService(
        (_, __, ___) async => _resp(_envelope()),
      );
      final ObservationPuller puller = ObservationPuller(
        VmServiceClient.forTest(fake, 'iso-1'),
      );

      await puller.pull(coreBudgetBytes: 131072);
      expect(fake.lastArgs, containsPair('coreBudgetBytes', '131072'));

      await puller.pull();
      expect(fake.lastArgs, isNot(contains('coreBudgetBytes')));
    });

    test('rejects an envelope-less response with isolate and keys', () async {
      final _FakeVmService fake = _FakeVmService(
        (_, __, ___) async => _resp(<String, dynamic>{
          'type': 'Observation',
          'error': 'missing value',
        }),
      );
      final VmServiceClient client = VmServiceClient.forTest(
        fake,
        'panel-isolate',
      );
      final ObservationPuller puller = ObservationPuller(client);

      await expectLater(
        puller.pull(),
        throwsA(
          isA<ObservationEnvelopeError>()
              .having(
                (ObservationEnvelopeError error) => error.isolateId,
                'isolateId',
                'panel-isolate',
              )
              .having(
                (ObservationEnvelopeError error) => error.topLevelKeys,
                'topLevelKeys',
                <String>['error', 'type'],
              ),
        ),
      );
    });

    test('rejects value carrying neither supported host shape', () async {
      final _FakeVmService fake = _FakeVmService(
        (_, __, ___) async => _resp(<String, dynamic>{
          'type': 'Observation',
          'value': <String, dynamic>{'routes': <String>[]},
        }),
      );
      final ObservationPuller puller = ObservationPuller(
        VmServiceClient.forTest(fake, 'panel-isolate'),
      );

      await expectLater(
        puller.pull(),
        throwsA(isA<ObservationEnvelopeError>()),
      );
    });
  });
}
