import 'package:exploration_flutter/contract.dart';
import 'package:exploration_flutter/test_support/perception_serializer.dart';
import 'package:exploration_riverpod/exploration_riverpod.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_perception/genesis_perception.dart';

/// Build a plugin whose observer is installed on its container.
({RiverpodExplorationPlugin plugin, ProviderContainer container}) wired() {
  final observer = ExplorationProviderObserver();
  final container =
      ProviderContainer(observers: <ProviderObserver>[observer]);
  final plugin = RiverpodExplorationPlugin(
    container: container,
    observer: observer,
  );
  return (plugin: plugin, container: container);
}

/// Drive the plugin's observation exactly as the binding's single loop does:
/// prepareForObservation() (flush), then harvest the perception fragment.
Map<String, Object?> harvest(RiverpodExplorationPlugin plugin) {
  plugin.prepareForObservation();
  final PerceptionOwner owner = PerceptionOwner();
  try {
    final Branch root = owner.mountRoot(plugin.buildPerception());
    return serializePerceptionFragment(root);
  } finally {
    owner.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scheduler = SchedulerBinding.instance;
  PluginContext ctx() =>
      PluginContext(namespace: 'riverpod', scheduler: scheduler);

  test('namespace + tool name', () {
    final w = wired();
    addTearDown(w.container.dispose);
    expect(w.plugin.namespace, 'riverpod');
    expect(w.plugin.tools.single.name, 'invalidate_provider');
    final schema = w.plugin.tools.single.inputSchema.raw;
    expect(schema['type'], 'object');
    expect(schema['additionalProperties'], false);
    expect(schema['required'], <String>['provider_id']);
    expect(
      (schema['properties'] as Map)['provider_id'],
      <String, Object?>{'type': 'string'},
    );
    expect(w.plugin.tools.single.description, contains('provider_id'));
  });

  test('isPerceptionIdle before initialize is true', () async {
    final w = wired();
    addTearDown(w.container.dispose);
    w.plugin.prepareForObservation();
    expect(w.plugin.isPerceptionIdle(), isTrue);
  });

  test('isPerceptionIdle is true when container is empty', () async {
    final w = wired();
    addTearDown(w.container.dispose);
    await w.plugin.initialize(ctx());
    w.plugin.prepareForObservation();
    expect(w.plugin.isPerceptionIdle(), isTrue);
  });

  test('lists live providers, records change, and tool invalidates',
      () async {
    final counter = StateProvider<int>((r) => 0, name: 'counter');
    final w = wired();
    addTearDown(w.container.dispose);
    await w.plugin.initialize(ctx());
    // Trigger didAddProvider.
    expect(w.container.read(counter), 0);
    // Trigger didUpdateProvider.
    w.container.read(counter.notifier).state = 1;

    w.plugin.prepareForObservation();
    expect(w.plugin.isPerceptionIdle(), isFalse);
    final frag = harvest(w.plugin);
    expect(frag['invalidatable_providers'], contains('counter'));
    final ch = frag['recent_state_changes'] as List;
    // prepareForObservation() stamps the flush at turn 0 (production default).
    expect(
      ch.any((e) =>
          (e as Map)['provider_id'] == 'counter' && e['at_turn'] == 0),
      isTrue,
    );

    final res = await w.plugin.tools.single
        .call(<String, Object?>{'provider_id': 'counter'});
    expect(res.ok, isTrue);
  });

  test('tool reports unknown provider_id and bad input', () async {
    final w = wired();
    addTearDown(w.container.dispose);
    await w.plugin.initialize(ctx());

    final missing = await w.plugin.tools.single.call(const <String, Object?>{});
    expect(missing.ok, isFalse);
    expect(missing.error, contains('provider_id'));

    final unknown = await w.plugin.tools.single
        .call(const <String, Object?>{'provider_id': 'nope'});
    expect(unknown.ok, isFalse);
    expect(unknown.error, contains('unknown provider_id'));
  });

  test('busyState idle + onActionExecuted no-op + dispose clears',
      () async {
    final w = wired();
    addTearDown(w.container.dispose);
    await w.plugin.initialize(ctx());
    expect((await w.plugin.busyState()).isBusy, isFalse);
    await w.plugin.onActionExecuted(const ExecutedAction(
      toolName: 'core.tap',
      args: <String, Object?>{},
      result: ToolResult(ok: true),
    ));
    await w.plugin.dispose();
    w.plugin.prepareForObservation();
    expect(w.plugin.isPerceptionIdle(), isTrue);
  });
}
