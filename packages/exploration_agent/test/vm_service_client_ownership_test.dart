/// Regression for lenny-wisp-0go2a.3: a BORROWED [VmServiceClient] (built
/// via `fromVmService` — e.g. DevTools reusing the shared
/// `serviceManager.service`) must NOT dispose the underlying [VmService] on
/// teardown, while an OWNING client (`connect`) must. The old unconditional
/// `dispose() => _vm.dispose()` tore down DevTools' shared connection on
/// every session end, which read as "the app exits when core.done is called".
library;

import 'dart:async';

import 'package:exploration_agent/exploration_agent.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

class _RecordingVmService extends VmService {
  // Feed an OPEN inbound stream: VmService auto-disposes when its input
  // stream is done, so a `Stream.empty()` would inflate [disposeCalls]
  // with the base class's own teardown. The caller closes [inbound] in a
  // tearDown after assertions have run.
  _RecordingVmService(StreamController<dynamic> inbound)
    : super(inbound.stream, (_) {});

  int disposeCalls = 0;

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) async {
    // Canned handshake so ExplorationSession.start() can complete.
    return Response()
      ..json = <String, dynamic>{
        'contractVersion': '1.0.0',
        'plugins': <Map<String, dynamic>>[],
      };
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

void main() {
  late StreamController<dynamic> inbound;
  late _RecordingVmService vm;

  setUp(() {
    inbound = StreamController<dynamic>();
    vm = _RecordingVmService(inbound);
  });
  tearDown(() => inbound.close());

  test(
    'borrowed client (fromVmService) does NOT dispose the shared connection',
    () async {
      final client = VmServiceClient.fromVmService(vm, 'iso-1');

      await client.dispose();

      expect(
        vm.disposeCalls,
        0,
        reason: 'a connection the client did not create must survive teardown',
      );
    },
  );

  test(
    'owning client (connect-path) DOES dispose its own connection',
    () async {
      // forTest(ownsConnection: true) mirrors the `connect()` ownership.
      final client = VmServiceClient.forTest(vm, 'iso-1', ownsConnection: true);

      await client.dispose();

      expect(vm.disposeCalls, 1);
    },
  );

  test(
    'ExplorationSession.fromVmService.end() leaves the borrowed VM alive',
    () async {
      final session = ExplorationSession.fromVmService(vm, 'iso-1');
      await session.start('goal', const ExplorationConfig());

      await session.end();

      expect(
        vm.disposeCalls,
        0,
        reason: 'panel teardown must not kill the shared serviceManager link',
      );
    },
  );
}
