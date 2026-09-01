import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

import '../support/leonard_vm_service_fake.dart';

const Map<String, dynamic> _handshake = <String, dynamic>{
  'protocolVersion': '2',
  'extensions': <Map<String, dynamic>>[
    <String, dynamic>{
      'namespace': 'core',
      'tools': <String>['tap'],
    },
  ],
  'capabilities': <String>[],
};

const Map<String, dynamic> _observation = <String, dynamic>{
  'semantics': <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 1,
      'role': 'tab',
      'label': 'Conversation',
      'rect': <int>[0, 0, 120, 40],
    },
  ],
  'routes': <String>[],
  'errors': <dynamic>[],
  'stability': <String, dynamic>{
    'policy': 'action-relative',
    'terminated_by': 'idle',
    'duration_ms': 1,
    'framework_busy': false,
    'extensions_busy': <dynamic>[],
  },
  'extensions': <String, dynamic>{},
};

LeonardVmServiceFake _fake(List<IsolateRef> isolates) {
  return LeonardVmServiceFake(
    vmIsolates: isolates,
    handshakeResponse: _handshake,
    observationBundle: _observation,
  );
}

void main() {
  group('VmServiceClient DWDS connect path', () {
    test('pins the DWDS isolate through handshake and observation', () async {
      final LeonardVmServiceFake fake = _fake(<IsolateRef>[
        IsolateRef(id: '1', name: 'main'),
      ]);
      final VmServiceClient client = await VmServiceClient.connectForTest(fake);
      final LeonardSession session = LeonardSession.forTest(client);

      try {
        await session.start('probe panel', const LeonardConfig());
        final Observation observation = await session.observe();

        expect(fake.getVmCalls, 1);
        expect(session.handshake.contractVersion, '2');
        expect(session.handshake.extensions.single.namespace, 'core');
        expect(observation.core.nodes, isNotEmpty);
        expect(
          fake.calls.map((FakeRpcCall call) => call.method).toList(),
          <String>[
            'ext.leonard.core.handshake',
            'ext.leonard.core.get_stable_observation',
          ],
        );
        expect(
          fake.calls.every((FakeRpcCall call) => call.isolateId == '1'),
          isTrue,
        );
        expect(fake.calls.last.args, <String, dynamic>{
          'policy': 'action-relative',
        });
      } finally {
        await session.end();
      }
    });

    test('fails loudly when DWDS reports no isolates', () async {
      final LeonardVmServiceFake fake = _fake(const <IsolateRef>[]);

      await expectLater(
        VmServiceClient.connectForTest(fake),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.toString(),
            'message',
            contains('no isolates'),
          ),
        ),
      );
      expect(fake.getVmCalls, 1);
      expect(fake.calls, isEmpty);
    });

    test('fails loudly when the DWDS isolate has no id', () async {
      final LeonardVmServiceFake fake = _fake(<IsolateRef>[
        IsolateRef(name: 'main'),
      ]);

      await expectLater(
        VmServiceClient.connectForTest(fake),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.toString(),
            'message',
            contains('First isolate has no id'),
          ),
        ),
      );
      expect(fake.getVmCalls, 1);
      expect(fake.calls, isEmpty);
    });
  });
}
