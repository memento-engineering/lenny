/// AC2 — `MultiHostSession.forTest` attaches N channels, each pinning its
/// own client; per-client dispatch; dispose respects ownership (m3).
library;

import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

import '_fakes.dart';

void main() {
  group('MultiHostSession.forTest (AC2)', () {
    test('routes each namespace to its OWN client', () async {
      final RecordingVmService vmA = RecordingVmService(
        extensions: <Map<String, dynamic>>[
          ext('core', <String>['tap']),
        ],
      );
      final RecordingVmService vmB = RecordingVmService(
        extensions: <Map<String, dynamic>>[
          ext('native', <String>['tap']),
        ],
      );
      final MultiHostSession session = MultiHostSession.forTest(
        <VmServiceClient>[clientOver(vmA), clientOver(vmB)],
      );
      await session.start('goal', const LeonardConfig());

      await session.executeAction('core.tap', <String, dynamic>{'node_id': 5});
      await session.executeAction('native.tap', <String, dynamic>{
        'label': 'Email',
      });

      // core.tap landed on A (and NOT B); native.tap landed on B (and NOT A).
      expect(
        vmA.calls.map((RecordedCall c) => c.method),
        contains('ext.exploration.core.tap'),
      );
      expect(
        vmA.calls.map((RecordedCall c) => c.method),
        isNot(contains('ext.exploration.native.tap')),
      );
      expect(
        vmB.calls.map((RecordedCall c) => c.method),
        contains('ext.exploration.native.tap'),
      );
      expect(
        vmB.calls.map((RecordedCall c) => c.method),
        isNot(contains('ext.exploration.core.tap')),
      );
    });

    test(
      'end() disposes each channel; owned dispose, borrowed no-ops',
      () async {
        final RecordingVmService owned = RecordingVmService(
          extensions: <Map<String, dynamic>>[
            ext('core', <String>['tap']),
          ],
        );
        final RecordingVmService borrowed = RecordingVmService(
          extensions: <Map<String, dynamic>>[
            ext('native', <String>['tap']),
          ],
        );
        final MultiHostSession session =
            MultiHostSession.forTest(<VmServiceClient>[
              clientOver(owned, ownsConnection: true),
              clientOver(borrowed, ownsConnection: false),
            ]);
        await session.start('goal', const LeonardConfig());

        await session.end();

        // Owned connection disposed exactly once; borrowed never torn down.
        expect(owned.disposeCount, equals(1));
        expect(borrowed.disposeCount, equals(0));

        // end() is idempotent.
        await session.end();
        expect(owned.disposeCount, equals(1));
      },
    );
  });
}
