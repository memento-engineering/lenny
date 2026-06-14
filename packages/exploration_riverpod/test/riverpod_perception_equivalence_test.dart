library;

import 'dart:convert';
import 'dart:io';

import 'package:exploration_flutter/contract.dart';
import 'package:exploration_flutter/test_support/observation_equivalence.dart';
import 'package:exploration_flutter/test_support/perception_serializer.dart';
import 'package:exploration_riverpod/exploration_riverpod.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_perception/genesis_perception.dart';

/// Build a plugin whose observer is installed on its container.
({RiverpodExplorationPlugin plugin, ProviderContainer container}) _wired({
  int budget = 1024,
}) {
  final ExplorationProviderObserver observer = ExplorationProviderObserver();
  final ProviderContainer container =
      ProviderContainer(observers: <ProviderObserver>[observer]);
  final RiverpodExplorationPlugin plugin = RiverpodExplorationPlugin(
    container: container,
    observer: observer,
    observationBudgetBytes: budget,
  );
  return (plugin: plugin, container: container);
}

Map<String, Object?> _harvestFragment(RiverpodExplorationPlugin plugin) {
  final PerceptionOwner owner = PerceptionOwner();
  try {
    final Branch root = owner.mountRoot(plugin.buildPerception());
    return serializePerceptionFragment(root);
  } finally {
    owner.dispose();
  }
}

Map<String, Object?> _wrapObs(Map<String, Object?> riverpodFrag) =>
    <String, Object?>{
      'semantics': <Object?>[],
      'routes': <Object?>[],
      'errors': <Object?>[],
      'stability': <String, Object?>{},
      'plugins': <String, Object?>{'riverpod': riverpodFrag},
    };

/// Resolve the committed golden regardless of the cwd the runner uses.
File _goldenFile() {
  const String rel =
      'packages/exploration_flutter/test/goldens/riverpod.observation.json';
  for (final String prefix in <String>[
    '../exploration_flutter/test/goldens/riverpod.observation.json',
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

  PluginContext ctx() =>
      PluginContext(namespace: 'riverpod', scheduler: scheduler);
  ObservationContext oc(int t) =>
      ObservationContext(turn: t, sinceLastAction: Duration.zero);

  test(
      'live providers + change: perception fragment equals legacy fragment',
      () async {
    final ({
      RiverpodExplorationPlugin plugin,
      ProviderContainer container
    }) w = _wired();
    addTearDown(w.container.dispose);
    await w.plugin.initialize(ctx());

    final StateProvider<int> counter =
        StateProvider<int>((Ref r) => 0, name: 'counter');
    // didAddProvider
    expect(w.container.read(counter), 0);
    // didUpdateProvider -> _pending
    w.container.read(counter.notifier).state = 1;

    // observe() FIRST: flushes _pending into the ring stamped at_turn:3.
    // This mirrors the binding (observeAll before the perception loop), so the
    // ring is in the same drained state when the perception build reads it.
    final Map<String, Object?>? legacy = await w.plugin.observe(oc(3));
    expect(legacy, isNotNull,
        reason: 'legacy observe() must emit with a live provider + change');

    final Map<String, Object?> perceptionFrag = _harvestFragment(w.plugin);

    assertObservationEquivalent(
      _wrapObs(legacy!),
      _wrapObs(perceptionFrag),
    );
  });

  test('idle state: legacy observe() returns null (null-gate suppresses ns)',
      () async {
    final ({
      RiverpodExplorationPlugin plugin,
      ProviderContainer container
    }) w = _wired();
    addTearDown(w.container.dispose);
    await w.plugin.initialize(ctx());

    // No providers read — plugin is idle.
    final Map<String, Object?>? legacy = await w.plugin.observe(oc(0));
    expect(legacy, isNull,
        reason: 'legacy observe() must return null when idle');

    // buildPerception() on an empty observer emits non-null empty-list Fields;
    // the binding null-gate (exploration_binding.dart: rawFragments[ns]==null
    // -> continue) is what suppresses the riverpod ns. Document the stable
    // empty shape so the gate's single source of truth (observe()==null) holds.
    final Map<String, Object?> perceptionFrag = _harvestFragment(w.plugin);
    expect(perceptionFrag, <String, Object?>{
      'invalidatable_providers': <String>[],
      'recent_state_changes': <Map<String, Object?>>[],
    });
  });

  test('golden: perception fragment matches committed riverpod golden',
      () async {
    final ({
      RiverpodExplorationPlugin plugin,
      ProviderContainer container
    }) w = _wired();
    addTearDown(w.container.dispose);
    await w.plugin.initialize(ctx());

    // Fixture matching goldens/riverpod.observation.json:
    //   live providers: userListProvider, authStateProvider (in that order)
    //   one recorded change: {provider_id: userListProvider, at_turn: 2}
    final StateProvider<int> userListProvider =
        StateProvider<int>((Ref r) => 0, name: 'userListProvider');
    final StateProvider<int> authStateProvider =
        StateProvider<int>((Ref r) => 0, name: 'authStateProvider');

    // didAddProvider in declared order -> live map insertion order.
    expect(w.container.read(userListProvider), 0);
    expect(w.container.read(authStateProvider), 0);
    // didUpdateProvider only on userListProvider -> single pending change.
    w.container.read(userListProvider.notifier).state = 1;

    // Flush the pending change stamped at_turn:2.
    final Map<String, Object?>? legacy = await w.plugin.observe(oc(2));
    expect(legacy, isNotNull);

    final Map<String, Object?> perceptionFrag = _harvestFragment(w.plugin);

    final Map<String, Object?> golden = (jsonDecode(
      _goldenFile().readAsStringSync(),
    ) as Map<String, Object?>);
    final Map<String, Object?> goldenRiverpod =
        (golden['plugins'] as Map<String, Object?>)['riverpod']
            as Map<String, Object?>;

    // Pin the plugin fragment byte-for-byte against the committed golden:
    // key names AND declared order via canonical JSON encoding.
    expect(
      jsonEncode(perceptionFrag),
      jsonEncode(goldenRiverpod),
      reason: 'perception fragment must be byte-equivalent to the golden '
          'riverpod fragment (key names + order)',
    );

    // And via the equivalence gate against the full golden observation: reuse
    // the golden's non-plugin envelope, swap in the harvested fragment.
    final Map<String, Object?> harvestedObs = <String, Object?>{
      'semantics': golden['semantics'],
      'routes': golden['routes'],
      'errors': golden['errors'],
      'stability': golden['stability'],
      'plugins': <String, Object?>{'riverpod': perceptionFrag},
    };
    assertObservationEquivalent(golden, harvestedObs);
  });
}
