/// Regression test for the web-safe construction path: building a
/// [VmServiceClient] / [LeonardSession] from an already-connected
/// [VmService] must not require `package:vm_service/vm_service_io.dart`
/// (which pulls in `dart:io` and crashes on web with
/// `Unsupported operation: Platform._version`). See lenny-dzh.
library;

import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

/// Hand-rolled fake — overrides only [callServiceExtension].
class _FakeVmService extends VmService {
  _FakeVmService() : super(const Stream<dynamic>.empty(), (_) {});

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) async {
    final r = Response();
    r.json = <String, dynamic>{
      'contractVersion': '1.0.0',
      'extensions': <Map<String, dynamic>>[],
    };
    return r;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test(
    'VmServiceClient.fromVmService handshakes without vm_service_io',
    () async {
      final client = VmServiceClient.fromVmService(_FakeVmService(), 'iso-1');
      final result = await client.handshake();
      expect(result.plugins, isEmpty);
      expect(result.contractVersion, equals('1.0.0'));
    },
  );

  test('LeonardSession.fromVmService starts without vm_service_io', () async {
    final session = LeonardSession.fromVmService(_FakeVmService(), 'iso-1');
    await session.start('goal', const LeonardConfig());
    expect(session.handshake.plugins, isEmpty);
    await session.end();
  });
}
