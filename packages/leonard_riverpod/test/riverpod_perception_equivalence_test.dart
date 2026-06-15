library;

import 'dart:convert';
import 'dart:io';

import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/test_support/observation_equivalence.dart';
import 'package:leonard_flutter/test_support/perception_serializer.dart';
import 'package:leonard_riverpod/leonard_riverpod.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_perception/genesis_perception.dart';

/// Build a extension whose observer is installed on its container.
({
  RiverpodLeonardExtension plugin,
  ProviderContainer container,
  LeonardProviderObserver observer,
})
_wired() {
  final LeonardProviderObserver observer = LeonardProviderObserver();
  final ProviderContainer container = ProviderContainer(
    observers: <ProviderObserver>[observer],
  );
  final RiverpodLeonardExtension plugin = RiverpodLeonardExtension(
    container: container,
    observer: observer,
  );
  return (plugin: plugin, container: container, observer: observer);
}

Map<String, Object?> _harvestFragment(RiverpodLeonardExtension plugin) {
  final PerceptionOwner owner = PerceptionOwner();
  try {
    final Branch root = owner.mountRoot(plugin.buildPerception());
    return serializePerceptionFragment(root);
  } finally {
    owner.dispose();
  }
}

/// Resolve the committed golden regardless of the cwd the runner uses.
File _goldenFile() {
  const String rel =
      'packages/leonard_flutter/test/goldens/riverpod.observation.json';
  for (final String prefix in <String>[
    '../leonard_flutter/test/goldens/riverpod.observation.json',
    rel,
    '../../$rel',
  ]) {
    final File f = File(prefix);
    if (f.existsSync()) return f;
  }
  throw StateError('riverpod golden not found from ${Directory.current.path}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final SchedulerBinding scheduler = SchedulerBinding.instance;

  ExtensionContext ctx() =>
      ExtensionContext(namespace: 'riverpod', scheduler: scheduler);

  test(
    'live providers + change: perception fragment surfaces the change',
    () async {
      final w = _wired();
      addTearDown(w.container.dispose);
      await w.plugin.initialize(ctx());

      final StateProvider<int> counter = StateProvider<int>(
        (Ref r) => 0,
        name: 'counter',
      );
      // didAddProvider
      expect(w.container.read(counter), 0);
      // didUpdateProvider -> _pending
      w.container.read(counter.notifier).state = 1;

      // prepareForObservation() flushes _pending into the ring (turn 0),
      // exactly as the binding does before reading the perception fragment.
      w.plugin.prepareForObservation();
      expect(w.plugin.isPerceptionIdle(), isFalse);

      final Map<String, Object?> perceptionFrag = _harvestFragment(w.plugin);
      expect(perceptionFrag['invalidatable_providers'], contains('counter'));
      final List<Object?> ch =
          perceptionFrag['recent_state_changes']! as List<Object?>;
      expect(
        ch.any((Object? e) {
          final Map<Object?, Object?> m = e! as Map<Object?, Object?>;
          return m['provider_id'] == 'counter' && m['at_turn'] == 0;
        }),
        isTrue,
      );
    },
  );

  test(
    'idle state: isPerceptionIdle() is true (binding suppresses the ns)',
    () async {
      final w = _wired();
      addTearDown(w.container.dispose);
      await w.plugin.initialize(ctx());

      // No providers read — extension is idle.
      w.plugin.prepareForObservation();
      expect(
        w.plugin.isPerceptionIdle(),
        isTrue,
        reason: 'isPerceptionIdle() must be true when idle',
      );

      // buildPerception() on an empty observer emits non-null empty-list Fields;
      // the binding's isPerceptionIdle() gate is what suppresses the riverpod
      // ns. Document the stable empty shape.
      final Map<String, Object?> perceptionFrag = _harvestFragment(w.plugin);
      expect(perceptionFrag, <String, Object?>{
        'invalidatable_providers': <String>[],
        'recent_state_changes': <Map<String, Object?>>[],
      });
    },
  );

  test(
    'golden: perception fragment matches committed riverpod golden',
    () async {
      final w = _wired();
      addTearDown(w.container.dispose);
      await w.plugin.initialize(ctx());

      // Fixture matching goldens/riverpod.observation.json:
      //   live providers: userListProvider, authStateProvider (in that order)
      //   one recorded change: {provider_id: userListProvider, at_turn: 2}
      final StateProvider<int> userListProvider = StateProvider<int>(
        (Ref r) => 0,
        name: 'userListProvider',
      );
      final StateProvider<int> authStateProvider = StateProvider<int>(
        (Ref r) => 0,
        name: 'authStateProvider',
      );

      // didAddProvider in declared order -> live map insertion order.
      expect(w.container.read(userListProvider), 0);
      expect(w.container.read(authStateProvider), 0);
      // didUpdateProvider only on userListProvider -> single pending change.
      w.container.read(userListProvider.notifier).state = 1;

      // The golden's at_turn:2 is a curated fixture. Production flushes at
      // turn 0; drive the observer ring directly to stamp the change at turn 2
      // so the harvested fragment is byte-equivalent to the committed golden.
      w.observer.flushPendingAt(2);

      final Map<String, Object?> perceptionFrag = _harvestFragment(w.plugin);

      final Map<String, Object?> golden =
          (jsonDecode(_goldenFile().readAsStringSync())
              as Map<String, Object?>);
      final Map<String, Object?> goldenRiverpod =
          (golden['extensions'] as Map<String, Object?>)['riverpod']
              as Map<String, Object?>;

      // Pin the extension fragment byte-for-byte against the committed golden:
      // key names AND declared order via canonical JSON encoding.
      expect(
        jsonEncode(perceptionFrag),
        jsonEncode(goldenRiverpod),
        reason:
            'perception fragment must be byte-equivalent to the golden '
            'riverpod fragment (key names + order)',
      );

      // And via the equivalence gate against the full golden observation: reuse
      // the golden's non-extension envelope, swap in the harvested fragment.
      final Map<String, Object?> harvestedObs = <String, Object?>{
        'semantics': golden['semantics'],
        'routes': golden['routes'],
        'errors': golden['errors'],
        'stability': golden['stability'],
        'extensions': <String, Object?>{'riverpod': perceptionFrag},
      };
      assertObservationEquivalent(golden, harvestedObs);
    },
  );
}
