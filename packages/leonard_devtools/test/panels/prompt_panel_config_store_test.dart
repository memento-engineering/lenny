library;

import 'package:leonard_devtools/src/panels/prompt_panel_config.dart';
import 'package:leonard_devtools/src/panels/prompt_panel_config_store.dart';
import 'package:flutter_test/flutter_test.dart';

PromptPanelConfig _cfg({
  String goal = '',
  Set<String> enabled = const <String>{},
}) => PromptPanelConfig(
  goal: goal,
  modelId: '',
  maxTurns: 50,
  wallClockBudget: const Duration(minutes: 15),
  enabledExtensionNamespaces: enabled,
);

void main() {
  group('InMemoryPromptPanelConfigStore', () {
    test('returns null when empty', () async {
      final store = InMemoryPromptPanelConfigStore();
      final result = await store.load(liveNamespaces: {'router'});
      expect(result, isNull);
    });

    test('round-trips goal, maxTurns, budget', () async {
      final store = InMemoryPromptPanelConfigStore();
      await store.save(
        PromptPanelConfig(
          goal: 'my goal',
          modelId: '',
          maxTurns: 30,
          wallClockBudget: const Duration(minutes: 8),
          enabledExtensionNamespaces: const <String>{},
        ),
        knownNamespaces: const <String>{},
      );
      final loaded = await store.load(liveNamespaces: const <String>{});
      expect(loaded, isNotNull);
      expect(loaded!.goal, 'my goal');
      expect(loaded.maxTurns, 30);
      expect(loaded.wallClockBudget, const Duration(minutes: 8));
    });

    test('new namespace (not in known) defaults to enabled', () async {
      final store = InMemoryPromptPanelConfigStore();
      await store.save(_cfg(enabled: {'router'}), knownNamespaces: {'router'});
      final loaded = await store.load(liveNamespaces: {'router', 'newPlugin'});
      expect(
        loaded!.enabledExtensionNamespaces,
        containsAll(['router', 'newPlugin']),
      );
    });

    test('disabled namespace stays disabled', () async {
      final store = InMemoryPromptPanelConfigStore();
      // 'dio' known at save time but not enabled
      await store.save(
        _cfg(enabled: {'router'}),
        knownNamespaces: {'router', 'dio'},
      );
      final loaded = await store.load(liveNamespaces: {'router', 'dio'});
      expect(loaded!.enabledExtensionNamespaces, contains('router'));
      expect(loaded.enabledExtensionNamespaces, isNot(contains('dio')));
    });

    test('removed namespace dropped silently', () async {
      final store = InMemoryPromptPanelConfigStore();
      await store.save(
        _cfg(enabled: {'router', 'old'}),
        knownNamespaces: {'router', 'old'},
      );
      final loaded = await store.load(liveNamespaces: {'router'});
      expect(loaded!.enabledExtensionNamespaces, {'router'});
      expect(loaded.enabledExtensionNamespaces, isNot(contains('old')));
    });
  });

  group('DtdPromptPanelConfigStore', () {
    test('falls back to localRead when DTD returns null', () async {
      String? localStored;
      final store = DtdPromptPanelConfigStore(
        read: (_) async => null,
        write: (_, __) async {},
        localRead: (_) => localStored,
        localWrite: (_, v) => localStored = v,
      );
      // Save so local storage has data.
      await store.save(
        _cfg(goal: 'local goal'),
        knownNamespaces: const <String>{},
      );
      final loaded = await store.load(liveNamespaces: const <String>{});
      expect(loaded!.goal, 'local goal');
    });

    test('writes to both DTD and localWrite', () async {
      String? dtdStored;
      String? localStored;
      final store = DtdPromptPanelConfigStore(
        read: (_) async => dtdStored,
        write: (_, v) async => dtdStored = v,
        localRead: (_) => localStored,
        localWrite: (_, v) => localStored = v,
      );
      await store.save(_cfg(goal: 'g'), knownNamespaces: const <String>{});
      expect(dtdStored, isNotNull);
      expect(localStored, isNotNull);
      expect(dtdStored, localStored);
    });

    test('ignores corrupt JSON and returns null', () async {
      final store = DtdPromptPanelConfigStore(
        read: (_) async => '{not: valid json!!!',
        write: (_, __) async {},
      );
      final loaded = await store.load(liveNamespaces: const <String>{});
      expect(loaded, isNull);
    });

    test('null-callbacks are no-ops', () async {
      // No localRead/localWrite — save and load should not throw.
      String? dtdStored;
      final store = DtdPromptPanelConfigStore(
        read: (_) async => dtdStored,
        write: (_, v) async => dtdStored = v,
      );
      await expectLater(() async {
        await store.save(_cfg(goal: 'g'), knownNamespaces: const <String>{});
        await store.load(liveNamespaces: const <String>{});
      }, returnsNormally);
    });
  });
}
