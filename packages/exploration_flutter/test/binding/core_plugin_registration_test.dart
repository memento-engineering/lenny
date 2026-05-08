import 'package:exploration_flutter/contract.dart';
import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class _UserPluginClaimingCore extends ExplorationPlugin {
  _UserPluginClaimingCore();
  @override
  String get namespace => 'core';
  @override
  List<ExplorationTool> get tools => const <ExplorationTool>[];
  @override
  Future<void> initialize(PluginContext ctx) async {}
  @override
  Future<Map<String, Object?>?> observe(ObservationContext ctx) async => null;
  @override
  Future<BusyState> busyState() async => BusyState.idle;
  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}
  @override
  Future<void> dispose() async {}
}

class _UserPluginOk extends ExplorationPlugin {
  _UserPluginOk();
  @override
  String get namespace => 'router';
  @override
  List<ExplorationTool> get tools => const <ExplorationTool>[];
  @override
  Future<void> initialize(PluginContext ctx) async {}
  @override
  Future<Map<String, Object?>?> observe(ObservationContext ctx) async => null;
  @override
  Future<BusyState> busyState() async => BusyState.idle;
  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  late ExplorationBinding binding;

  setUpAll(() async {
    binding = ExplorationBinding.ensureInitialized(
      plugins: <ExplorationPlugin>[
        _UserPluginClaimingCore(),
        _UserPluginOk(),
      ],
    )!;
    // Plugin initialization runs in a microtask; flush it so VM service
    // extensions are registered before any extension lookup.
    await Future<void>.delayed(Duration.zero);
  });

  test(
    'host-installed CorePlugin reserves the "core" namespace; user plugin '
    'claiming "core" is skipped',
    () {
      final Map<String, ExplorationTool> merged =
          binding.pluginRegistry.mergedTools();
      const List<String> coreKeys = <String>[
        'core.tap',
        'core.long_press',
        'core.enter_text',
        'core.scroll',
        'core.scroll_until_visible',
        'core.gesture',
        'core.system_back',
        'core.wait',
        'core.inspect_widget',
        'core.done',
      ];
      for (final String k in coreKeys) {
        expect(merged.containsKey(k), isTrue, reason: 'missing $k');
      }
    },
  );

  test('merged tool map carries every core.<tool> entry', () {
    // Plugin VM service extensions are registered directly via
    // `dart:developer.registerExtension` from inside CorePlugin.initialize
    // (PluginContext path), not the binding's local
    // `_extensionCallbacks` map. The merged tool map is the
    // testable surface that proves all 10 tools made it through
    // registration end-to-end.
    final Map<String, ExplorationTool> merged =
        binding.pluginRegistry.mergedTools();
    const List<String> tools = <String>[
      'tap',
      'long_press',
      'enter_text',
      'scroll',
      'scroll_until_visible',
      'gesture',
      'system_back',
      'wait',
      'inspect_widget',
      'done',
    ];
    for (final String tool in tools) {
      expect(merged.containsKey('core.$tool'), isTrue,
          reason: 'tool core.$tool missing from merged map');
    }
  });

  test(
    'core.wait via the merged tool map rejects out-of-range seconds',
    () async {
      final ExplorationTool wait =
          binding.pluginRegistry.mergedTools()['core.wait']!;
      final ToolResult r =
          await wait.call(<String, Object?>{'seconds': 99});
      expect(r.ok, isFalse);
      expect(r.error, contains('schema_violation'));
    },
  );

  test(
    'core.wait via the merged tool map completes for an in-range delay',
    () async {
      final ExplorationTool wait =
          binding.pluginRegistry.mergedTools()['core.wait']!;
      final ToolResult r =
          await wait.call(<String, Object?>{'seconds': 0.05});
      expect(r.ok, isTrue, reason: r.error);
    },
  );
}

