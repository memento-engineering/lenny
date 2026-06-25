/// AC8, AC9 — the pure observation merge + per-fragment diff (m3).
///
/// No fakes: `mergeObservations` is value-in/value-out, and the existing
/// `ObservationDiffer` walks the merged shape unchanged.
library;

import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

Observation _flutterObs() => Observation(
  core: CoreFragment(
    routeStack: const <String>['/home'],
    nodes: <int, SemanticsNode>{
      1: const SemanticsNode(
        id: 1,
        role: 'button',
        label: 'Sign in',
        state: <String>[],
        actions: <String>['tap'],
        rect: <int>[0, 0, 100, 40],
      ),
    },
    errors: const <RuntimeError>[],
  ),
  extensions: <String, ExtensionFragment>{
    'router': ExtensionFragment.fromJson('router', <String, dynamic>{
      'route': '/home',
    }),
  },
  stability: StabilityMetadata(
    policy: 'action-relative',
    terminatedBy: 'idle',
    durationMs: 120,
    frameworkBusy: const <String, dynamic>{'phase': 'idle'},
    extensionsBusy: const <ExtensionBusy>[
      ExtensionBusy(namespace: 'router', reason: 'navigating'),
    ],
  ),
  screenshot: 'FLUTTER_PNG',
);

Observation _nativeObs() => Observation(
  core: CoreFragment.empty,
  extensions: <String, ExtensionFragment>{
    'native': ExtensionFragment.fromJson('native', <String, dynamic>{
      'fields': <String>['Email address', 'Password'],
    }),
  },
  stability: StabilityMetadata(
    policy: 'bounded-stability',
    terminatedBy: 'budget',
    durationMs: 500,
    frameworkBusy: const <String, dynamic>{'phase': 'native-busy'},
    extensionsBusy: const <ExtensionBusy>[
      ExtensionBusy(namespace: 'native', reason: 'webview-load'),
    ],
  ),
  screenshot: 'NATIVE_PNG',
);

void main() {
  group('mergeObservations (AC8)', () {
    test('places N fragments side-by-side; primary framework fields; '
        'concatenated extensionsBusy', () {
      final Observation flutterObs = _flutterObs();
      final Observation nativeObs = _nativeObs();
      final Observation merged = mergeObservations(<Observation>[
        flutterObs,
        nativeObs,
      ]);

      // core == the Flutter (primary) core verbatim.
      expect(merged.core, equals(flutterObs.core));
      expect(merged.core.nodes.containsKey(1), isTrue);

      // extensions: BOTH keys present, neither overwritten.
      expect(merged.extensions.keys, containsAll(<String>['router', 'native']));
      expect(
        merged.extensions['router'],
        equals(flutterObs.extensions['router']),
      );
      expect(
        merged.extensions['native'],
        equals(nativeObs.extensions['native']),
      );

      // stability framework fields from PRIMARY verbatim (NOT unioned).
      expect(merged.stability.policy, equals('action-relative'));
      expect(merged.stability.terminatedBy, equals('idle'));
      expect(merged.stability.durationMs, equals(120));
      expect(
        merged.stability.frameworkBusy,
        equals(<String, dynamic>{'phase': 'idle'}),
      );

      // extensionsBusy CONCATENATED across hosts (primary first).
      expect(merged.stability.extensionsBusy.length, equals(2));
      expect(
        merged.stability.extensionsBusy.map((ExtensionBusy b) => b.namespace),
        equals(<String>['router', 'native']),
      );

      // screenshot from primary.
      expect(merged.screenshot, equals('FLUTTER_PNG'));
    });

    test('toJson round-trips with both extension fragments present', () {
      final Observation merged = mergeObservations(<Observation>[
        _flutterObs(),
        _nativeObs(),
      ]);
      final Map<String, dynamic> json = merged.toJson();
      final Map<String, dynamic> exts = (json['extensions'] as Map)
          .cast<String, dynamic>();
      expect(exts.keys, containsAll(<String>['router', 'native']));
    });

    test('core falls through to first non-empty in attach order', () {
      // If the primary core were empty but a later host had core, take that.
      final Observation empty = Observation(
        core: CoreFragment.empty,
        extensions: const <String, ExtensionFragment>{},
        stability: StabilityMetadata.empty,
      );
      final Observation withCore = _flutterObs();
      final Observation merged = mergeObservations(<Observation>[
        empty,
        withCore,
      ]);
      expect(merged.core, equals(withCore.core));
      // But framework fields still come from the PRIMARY (empty) host.
      expect(merged.stability.policy, equals(''));
    });

    test('throws on empty input', () {
      expect(
        () => mergeObservations(const <Observation>[]),
        throwsArgumentError,
      );
    });
  });

  group('merged observation diffs per-fragment (AC9)', () {
    test('only the native fragment changed → native delta, no-op core', () {
      final Observation merged0 = mergeObservations(<Observation>[
        _flutterObs(),
        _nativeObs(),
      ]);

      // Change only extensions['native']; keep Flutter core identical.
      final Observation nativeChanged = Observation(
        core: CoreFragment.empty,
        extensions: <String, ExtensionFragment>{
          'native': ExtensionFragment.fromJson('native', <String, dynamic>{
            'fields': <String>['Email address', 'Password', 'OTP'],
          }),
        },
        stability: _nativeObs().stability,
      );
      final Observation merged1 = mergeObservations(<Observation>[
        _flutterObs(),
        nativeChanged,
      ]);

      final ObservationDiff diff = ObservationDiffer.diff(merged0, merged1);

      // The native extension delta is reported (extensions is keyed by ns).
      expect(diff.extensions.containsKey('native'), isTrue);
      // core is unchanged (no node or route changes).
      expect(diff.core.nodesAdded, isEmpty);
      expect(diff.core.nodesRemoved, isEmpty);
      expect(diff.core.nodesChanged, isEmpty);
      expect(diff.core.routeChanges, isEmpty);
    });
  });
}
