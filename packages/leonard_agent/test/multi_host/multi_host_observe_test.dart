/// AC10 — observe(policy) applies one policy to ALL hosts and joins on all;
/// observeWithDiff advances the single merged baseline (m3).
library;

import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

import '_fakes.dart';

void main() {
  group('observe joins on all hosts (AC10)', () {
    test('one policy reaches both hosts; merged reflects both; slow host '
        'gates the turn', () async {
      final RecordingVmService fast = RecordingVmService(
        extensions: <Map<String, dynamic>>[
          ext('core', <String>['tap']),
        ],
        observation: <String, dynamic>{
          'routes': <String>['/home'],
          'extensions': <String, dynamic>{
            'router': <String, dynamic>{'route': '/home'},
          },
        },
      );
      final RecordingVmService slow = RecordingVmService(
        extensions: <Map<String, dynamic>>[
          ext('native', <String>['tap']),
        ],
        observeDelay: const Duration(milliseconds: 80),
        observation: <String, dynamic>{
          'extensions': <String, dynamic>{
            'native': <String, dynamic>{
              'fields': <String>['Email'],
            },
          },
        },
      );
      final MultiHostSession session = MultiHostSession.forTest(
        <VmServiceClient>[clientOver(fast), clientOver(slow)],
      );
      await session.start('goal', const LeonardConfig());

      final Stopwatch sw = Stopwatch()..start();
      final Observation merged = await session.observe(
        policy: StabilityPolicy.boundedStability,
      );
      sw.stop();

      // The merged observation reflects BOTH hosts' fragments.
      expect(merged.extensions.keys, containsAll(<String>['router', 'native']));

      // Both hosts got the SAME policy.
      RecordedCall obsCall(RecordingVmService vm) => vm.calls.firstWhere(
        (RecordedCall c) =>
            c.method == 'ext.exploration.core.get_stable_observation',
      );
      expect(obsCall(fast).args!['policy'], equals('bounded-stability'));
      expect(obsCall(slow).args!['policy'], equals('bounded-stability'));

      // The slow host gated the turn (join-on-all, not first-wins).
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(70));
    });

    test('observeWithDiff advances the single merged baseline', () async {
      final RecordingVmService a = RecordingVmService(
        extensions: <Map<String, dynamic>>[
          ext('core', <String>['tap']),
        ],
        observation: <String, dynamic>{
          'extensions': <String, dynamic>{
            'router': <String, dynamic>{'route': '/home'},
          },
        },
      );
      final RecordingVmService b = RecordingVmService(
        extensions: <Map<String, dynamic>>[
          ext('native', <String>['tap']),
        ],
        observation: <String, dynamic>{
          'extensions': <String, dynamic>{
            'native': <String, dynamic>{
              'fields': <String>['Email'],
            },
          },
        },
      );
      final MultiHostSession session = MultiHostSession.forTest(
        <VmServiceClient>[clientOver(a), clientOver(b)],
      );
      await session.start('goal', const LeonardConfig());

      // First diff is against the empty baseline → both fragments are ADDED.
      final ({Observation observation, ObservationDiff diff}) first =
          await session.observeWithDiff();
      expect(
        first.diff.extensions.keys,
        containsAll(<String>['router', 'native']),
      );
      expect(first.diff.extensions['router'], isA<ExtensionDiffAdded>());
      expect(first.diff.extensions['native'], isA<ExtensionDiffAdded>());

      // Second diff against the just-stored MERGED baseline → the same
      // fragments now diff opaque-against-prior (not "added"), proving the
      // single merged baseline advanced after the first observeWithDiff.
      final ({Observation observation, ObservationDiff diff}) second =
          await session.observeWithDiff();
      expect(second.diff.extensions['router'], isA<ExtensionDiffOpaque>());
      expect(second.diff.extensions['native'], isA<ExtensionDiffOpaque>());
    });
  });
}
