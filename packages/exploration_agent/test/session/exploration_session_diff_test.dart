import 'package:exploration_agent/exploration_agent.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

class _FakeVmService extends VmService {
  _FakeVmService(this._handler)
      : super(const Stream<dynamic>.empty(), (_) {});

  final Future<Response> Function(
    String method,
    String? isolateId,
    Map<String, dynamic>? args,
  ) _handler;

  String? lastMethod;
  Map<String, dynamic>? lastArgs;

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) {
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

Map<String, dynamic> _bundleA() => <String, dynamic>{
      'semantics': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'role': 'button',
          'label': 'A',
          'rect': <int>[0, 0, 10, 10],
        },
      ],
      'routes': <String>['/home'],
      'errors': const <Object>[],
      'stability': <String, dynamic>{
        'policy': 'action_relative',
        'terminated_by': 'idle',
        'duration_ms': 5,
        'framework_busy': <String, dynamic>{'anyBusy': false},
        'plugins_busy': const <Object>[],
      },
      'plugins': const <String, dynamic>{},
    };

Map<String, dynamic> _bundleB() => <String, dynamic>{
      'semantics': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'role': 'button',
          'label': 'B', // changed from A
          'rect': <int>[0, 0, 10, 10],
        },
        <String, dynamic>{
          'id': 2,
          'role': 'text',
          'rect': <int>[0, 20, 10, 30],
        },
      ],
      'routes': <String>['/home', '/details'],
      'errors': const <Object>[],
      'stability': <String, dynamic>{
        'policy': 'action_relative',
        'terminated_by': 'idle',
        'duration_ms': 8,
        'framework_busy': <String, dynamic>{'anyBusy': false},
        'plugins_busy': const <Object>[],
      },
      'plugins': const <String, dynamic>{},
    };

void main() {
  group('ExplorationSession.observeWithDiff', () {
    test('throws StateError before start()', () async {
      final _FakeVmService fake = _FakeVmService(
        (_, __, ___) async => _resp(<String, dynamic>{}),
      );
      final ExplorationSession session = ExplorationSession.forTest(
        VmServiceClient.forTest(fake, 'iso-1'),
      );
      await expectLater(
        session.observeWithDiff(),
        throwsA(isA<StateError>()),
      );
    });

    test('first call diffs against Observation.empty() (all-added)', () async {
      int call = 0;
      final _FakeVmService fake =
          _FakeVmService((String method, String? iso, Map<String, dynamic>? args) async {
        call++;
        if (method == 'ext.flutter.exploration.core.handshake') {
          return _resp(<String, dynamic>{
            'contractVersion': '1.0.0',
            'plugins': const <Object>[],
          });
        }
        return _resp(_bundleA());
      });
      final ExplorationSession session = ExplorationSession.forTest(
        VmServiceClient.forTest(fake, 'iso-1'),
      );
      await session.start('goal', const ExplorationConfig());

      final ({Observation observation, ObservationDiff diff}) result =
          await session.observeWithDiff();

      expect(
        fake.lastMethod,
        equals('ext.flutter.exploration.core.get_stable_observation'),
      );
      expect(fake.lastArgs, containsPair('policy', 'action_relative'));
      expect(result.observation.core.nodes.keys, equals(<int>{1}));
      // First-turn: all current nodes appear as added; nothing removed.
      expect(result.diff.core.nodesAdded.map((SemanticsNode n) => n.id),
          equals(<int>[1]));
      expect(result.diff.core.nodesRemoved, isEmpty);
      expect(result.diff.core.routeChanges, hasLength(1));
      expect(call, greaterThanOrEqualTo(2)); // handshake + observation
    });

    test('second call diffs against the first call’s result', () async {
      int obsCall = 0;
      final _FakeVmService fake =
          _FakeVmService((String method, String? iso, Map<String, dynamic>? args) async {
        if (method == 'ext.flutter.exploration.core.handshake') {
          return _resp(<String, dynamic>{
            'contractVersion': '1.0.0',
            'plugins': const <Object>[],
          });
        }
        obsCall++;
        return _resp(obsCall == 1 ? _bundleA() : _bundleB());
      });
      final ExplorationSession session = ExplorationSession.forTest(
        VmServiceClient.forTest(fake, 'iso-1'),
      );
      await session.start('goal', const ExplorationConfig());

      await session.observeWithDiff(); // turn 1: stores _prev = A
      final ({Observation observation, ObservationDiff diff}) result =
          await session.observeWithDiff(); // turn 2: A -> B

      // Node 2 newly present, node 1 changed (label A -> B), nothing removed.
      expect(result.diff.core.nodesAdded.map((SemanticsNode n) => n.id),
          equals(<int>[2]));
      expect(result.diff.core.nodesRemoved, isEmpty);
      expect(result.diff.core.nodesChanged, hasLength(1));
      expect(result.diff.core.nodesChanged.first.curr.id, equals(1));
      expect(result.diff.core.nodesChanged.first.prev.label, equals('A'));
      expect(result.diff.core.nodesChanged.first.curr.label, equals('B'));
      expect(result.diff.core.routeChanges, hasLength(1));
      expect(result.diff.core.routeChanges.first.previous,
          equals(<String>['/home']));
      expect(result.diff.core.routeChanges.first.current,
          equals(<String>['/home', '/details']));
    });

    test('threads a non-default policy onto the wire', () async {
      final _FakeVmService fake =
          _FakeVmService((String method, String? iso, Map<String, dynamic>? args) async {
        if (method == 'ext.flutter.exploration.core.handshake') {
          return _resp(<String, dynamic>{
            'contractVersion': '1.0.0',
            'plugins': const <Object>[],
          });
        }
        return _resp(_bundleA());
      });
      final ExplorationSession session = ExplorationSession.forTest(
        VmServiceClient.forTest(fake, 'iso-1'),
      );
      await session.start('goal', const ExplorationConfig());

      await session.observeWithDiff(policy: StabilityPolicy.boundedStability);
      expect(fake.lastArgs, containsPair('policy', 'bounded_stability'));
    });
  });
}
