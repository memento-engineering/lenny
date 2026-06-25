/// AC5, AC6 — tool routing to the owning host; unknown/malformed names are
/// hard errors thrown synchronously before any wire call (m3).
library;

import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

import '_fakes.dart';

void main() {
  late RecordingVmService vmA; // owns core + router
  late RecordingVmService vmB; // owns native
  late MultiHostSession session;

  Future<void> startSession() async {
    vmA = RecordingVmService(
      extensions: <Map<String, dynamic>>[
        ext('core', <String>['tap']),
        ext('router', <String>['go']),
      ],
    );
    vmB = RecordingVmService(
      extensions: <Map<String, dynamic>>[
        ext('native', <String>['tap']),
      ],
    );
    session = MultiHostSession.forTest(<VmServiceClient>[
      clientOver(vmA),
      clientOver(vmB),
    ]);
    await session.start('goal', const LeonardConfig());
  }

  group('routing (AC5)', () {
    test('core.* and router.* hit A; native.* hits B, args verbatim', () async {
      await startSession();

      await session.executeAction('core.tap', <String, dynamic>{'node_id': 1});
      await session.executeAction('router.go', <String, dynamic>{'to': '/x'});
      await session.executeAction('native.tap', <String, dynamic>{
        'label': 'Email',
      });

      final List<String> aMethods = vmA.calls
          .map((RecordedCall c) => c.method)
          .toList();
      final List<String> bMethods = vmB.calls
          .map((RecordedCall c) => c.method)
          .toList();
      expect(aMethods, contains('ext.exploration.core.tap'));
      expect(aMethods, contains('ext.exploration.router.go'));
      expect(bMethods, contains('ext.exploration.native.tap'));

      // Args are forwarded verbatim (JSON-encoded by the per-host client).
      final RecordedCall nativeCall = vmB.calls.firstWhere(
        (RecordedCall c) => c.method == 'ext.exploration.native.tap',
      );
      expect(nativeCall.args!['label'], equals('"Email"'));
    });
  });

  group('unknown / malformed namespace (AC6)', () {
    test(
      'unknown namespace throws MultiHostUnknownNamespace, no wire call',
      () async {
        await startSession();
        expect(
          () => session.executeAction('ghost.do', <String, dynamic>{}),
          throwsA(
            isA<MultiHostUnknownNamespace>()
                .having(
                  (MultiHostUnknownNamespace e) => e.namespace,
                  'namespace',
                  'ghost',
                )
                .having(
                  (MultiHostUnknownNamespace e) => e.known,
                  'known',
                  containsAll(<String>['core', 'router', 'native']),
                ),
          ),
        );
        // No fake received the call.
        expect(
          vmA.calls.where((RecordedCall c) => c.method.contains('ghost')),
          isEmpty,
        );
        expect(
          vmB.calls.where((RecordedCall c) => c.method.contains('ghost')),
          isEmpty,
        );
      },
    );

    test('malformed names throw ArgumentError (single-host parity)', () async {
      await startSession();
      expect(
        () => session.executeAction('bare', <String, dynamic>{}),
        throwsArgumentError,
      );
      expect(
        () => session.executeAction('core.', <String, dynamic>{}),
        throwsArgumentError,
      );
    });
  });
}
