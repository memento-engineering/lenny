import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

import '../../tool/panel_selfdrive_probe.dart';
import '../support/leonard_vm_service_fake.dart';

void main() {
  test('pins the first isolate and preserves both raw response maps', () async {
    final LeonardVmServiceFake fake = LeonardVmServiceFake(
      vmIsolates: <IsolateRef>[
        IsolateRef(id: 'panel-1', name: 'main'),
        IsolateRef(id: 'panel-2', name: 'stale'),
      ],
      handshakeResponse: <String, dynamic>{
        'protocolVersion': '2',
        'extensions': <dynamic>[],
      },
      observationBundle: <String, dynamic>{
        'semantics': <dynamic>[],
        'routes': <dynamic>[],
        'errors': <dynamic>[],
        'stability': <String, dynamic>{'policy': 'action-relative'},
        'extensions': <String, dynamic>{},
      },
    );

    final Map<String, Object?> result = await probePanelVmService(fake);

    expect(result['isolate_ids'], <String?>['panel-1', 'panel-2']);
    expect(result['isolate_id'], 'panel-1');
    expect(result['handshake'], <String, dynamic>{
      'protocolVersion': '2',
      'extensions': <dynamic>[],
    });
    expect(
      (result['observation'] as Map<String, dynamic>)['type'],
      'Observation',
    );
    expect(fake.calls, hasLength(2));
    expect(
      fake.calls.every((FakeRpcCall call) => call.isolateId == 'panel-1'),
      isTrue,
    );
  });

  test('fails loudly before extension calls when no isolate exists', () async {
    final LeonardVmServiceFake fake = LeonardVmServiceFake(
      handshakeResponse: <String, dynamic>{
        'protocolVersion': '2',
        'extensions': <dynamic>[],
      },
    );

    await expectLater(
      probePanelVmService(fake),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.toString(),
          'message',
          contains('no isolates'),
        ),
      ),
    );
    expect(fake.calls, isEmpty);
  });
}
