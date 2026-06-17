import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/test_support/perception_serializer.dart';
import 'package:leonard_riverpod/leonard_riverpod.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_perception/genesis_perception.dart';

/// Build an extension whose observer is installed on its container.
({RiverpodLeonardExtension extension, ProviderContainer container}) wired() {
  final observer = LeonardProviderObserver();
  final container = ProviderContainer(observers: <ProviderObserver>[observer]);
  final extension = RiverpodLeonardExtension(
    container: container,
    observer: observer,
  );
  return (extension: extension, container: container);
}

/// Drive the extension's observation exactly as the binding's single loop does:
/// prepareForObservation() (flush), then harvest the perception fragment.
Map<String, Object?> harvest(RiverpodLeonardExtension extension) {
  extension.prepareForObservation();
  final PerceptionOwner owner = PerceptionOwner();
  try {
    final Branch root = owner.mountRoot(extension.buildPerception());
    return serializePerceptionFragment(root);
  } finally {
    owner.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ExtensionContext ctx() => ExtensionContext(namespace: 'riverpod');

  test('namespace + tool name', () {
    final w = wired();
    addTearDown(w.container.dispose);
    expect(w.extension.namespace, 'riverpod');
    expect(w.extension.tools.single.name, 'invalidate_provider');
    final schema = w.extension.tools.single.inputSchema.raw;
    expect(schema['type'], 'object');
    expect(schema['additionalProperties'], false);
    expect(schema['required'], <String>['provider_id']);
    expect((schema['properties'] as Map)['provider_id'], <String, Object?>{
      'type': 'string',
    });
    expect(w.extension.tools.single.description, contains('provider_id'));
  });

  test('isPerceptionIdle before initialize is true', () async {
    final w = wired();
    addTearDown(w.container.dispose);
    w.extension.prepareForObservation();
    expect(w.extension.isPerceptionIdle(), isTrue);
  });

  test('isPerceptionIdle is true when container is empty', () async {
    final w = wired();
    addTearDown(w.container.dispose);
    await w.extension.initialize(ctx());
    w.extension.prepareForObservation();
    expect(w.extension.isPerceptionIdle(), isTrue);
  });

  test('lists live providers, records change, and tool invalidates', () async {
    final counter = StateProvider<int>((r) => 0, name: 'counter');
    final w = wired();
    addTearDown(w.container.dispose);
    await w.extension.initialize(ctx());
    // Trigger didAddProvider.
    expect(w.container.read(counter), 0);
    // Trigger didUpdateProvider.
    w.container.read(counter.notifier).state = 1;

    w.extension.prepareForObservation();
    expect(w.extension.isPerceptionIdle(), isFalse);
    final frag = harvest(w.extension);
    expect(frag['invalidatable_providers'], contains('counter'));
    final ch = frag['recent_state_changes'] as List;
    // prepareForObservation() stamps the flush at turn 0 (production default).
    expect(
      ch.any(
        (e) => (e as Map)['provider_id'] == 'counter' && e['at_turn'] == 0,
      ),
      isTrue,
    );

    final res = await w.extension.tools.single.call(<String, Object?>{
      'provider_id': 'counter',
    });
    expect(res.ok, isTrue);
  });

  test('tool reports unknown provider_id and bad input', () async {
    final w = wired();
    addTearDown(w.container.dispose);
    await w.extension.initialize(ctx());

    final missing = await w.extension.tools.single.call(const <String, Object?>{});
    expect(missing.ok, isFalse);
    expect(missing.error, contains('provider_id'));

    final unknown = await w.extension.tools.single.call(const <String, Object?>{
      'provider_id': 'nope',
    });
    expect(unknown.ok, isFalse);
    expect(unknown.error, contains('unknown provider_id'));
  });

  test('busyState idle + onActionExecuted no-op + dispose clears', () async {
    final w = wired();
    addTearDown(w.container.dispose);
    await w.extension.initialize(ctx());
    expect((await w.extension.busyState()).isBusy, isFalse);
    await w.extension.onActionExecuted(
      const ExecutedAction(
        toolName: 'core.tap',
        args: <String, Object?>{},
        result: ToolResult(ok: true),
      ),
    );
    await w.extension.dispose();
    w.extension.prepareForObservation();
    expect(w.extension.isPerceptionIdle(), isTrue);
  });
}
