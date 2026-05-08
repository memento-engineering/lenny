import 'dart:convert';

import 'package:exploration_flutter/contract.dart';
import 'package:exploration_riverpod/exploration_riverpod.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Build a plugin whose observer is installed on its container.
({RiverpodExplorationPlugin plugin, ProviderContainer container}) wired({
  int budget = 1024,
}) {
  final observer = ExplorationProviderObserver();
  final container =
      ProviderContainer(observers: <ProviderObserver>[observer]);
  final plugin = RiverpodExplorationPlugin(
    container: container,
    observer: observer,
    observationBudgetBytes: budget,
  );
  return (plugin: plugin, container: container);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scheduler = SchedulerBinding.instance;
  PluginContext ctx() =>
      PluginContext(namespace: 'riverpod', scheduler: scheduler);
  ObservationContext oc(int t) =>
      ObservationContext(turn: t, sinceLastAction: Duration.zero);

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

  test('observe before initialize returns null', () async {
    final w = wired();
    addTearDown(w.container.dispose);
    expect(await w.plugin.observe(oc(0)), isNull);
  });

  test('observe returns null when container is empty', () async {
    final w = wired();
    addTearDown(w.container.dispose);
    await w.plugin.initialize(ctx());
    expect(await w.plugin.observe(oc(1)), isNull);
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

    final frag = await w.plugin.observe(oc(3));
    expect(frag, isNotNull);
    expect(frag!['invalidatable_providers'], contains('counter'));
    final ch = frag['recent_state_changes'] as List;
    expect(
      ch.any((e) =>
          (e as Map)['provider_id'] == 'counter' && e['at_turn'] == 3),
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

  test('observation fragment respects 1024-byte budget with truncation',
      () async {
    final w = wired();
    addTearDown(w.container.dispose);
    for (var i = 0; i < 200; i++) {
      w.container.read(StateProvider<int>((r) => 0, name: 'p_$i'));
    }
    await w.plugin.initialize(ctx());
    final frag = await w.plugin.observe(oc(0));
    final encoded = utf8.encode(jsonEncode(frag));
    expect(encoded.length, lessThanOrEqualTo(1024));
    expect(frag!['truncated'], isTrue);
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
    expect(await w.plugin.observe(oc(0)), isNull);
  });
}
