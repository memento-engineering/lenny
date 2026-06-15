import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class _UserExtensionClaimingCore extends LeonardExtension {
  _UserExtensionClaimingCore();
  @override
  String get namespace => 'core';
  @override
  List<LeonardTool> get tools => const <LeonardTool>[];
  @override
  Future<void> initialize(ExtensionContext ctx) async {}
  @override
  Future<BusyState> busyState() async => BusyState.idle;
  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}
  @override
  Future<void> dispose() async {}
}

class _UserExtensionOk extends LeonardExtension {
  _UserExtensionOk();
  @override
  String get namespace => 'router';
  @override
  List<LeonardTool> get tools => const <LeonardTool>[];
  @override
  Future<void> initialize(ExtensionContext ctx) async {}
  @override
  Future<BusyState> busyState() async => BusyState.idle;
  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  late LeonardBinding binding;

  setUpAll(() async {
    binding = LeonardBinding.ensureInitialized(
      extensions: <LeonardExtension>[
        _UserExtensionClaimingCore(),
        _UserExtensionOk(),
      ],
    )!;
    // Extension initialization runs in a microtask; flush it so VM service
    // extensions are registered before any extension lookup.
    await Future<void>.delayed(Duration.zero);
  });

  test(
    'host-installed CoreExtension reserves the "core" namespace; user extension '
    'claiming "core" is skipped',
    () {
      final Map<String, LeonardTool> merged = binding.extensionRegistry
          .mergedTools();
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
    // Extension VM service extensions are registered directly via
    // `dart:developer.registerExtension` from inside CoreExtension.initialize
    // (ExtensionContext path), not the binding's local
    // `_extensionCallbacks` map. The merged tool map is the
    // testable surface that proves all 10 tools made it through
    // registration end-to-end.
    final Map<String, LeonardTool> merged = binding.extensionRegistry
        .mergedTools();
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
      expect(
        merged.containsKey('core.$tool'),
        isTrue,
        reason: 'tool core.$tool missing from merged map',
      );
    }
  });

  test(
    'core.wait via the merged tool map rejects out-of-range seconds',
    () async {
      final LeonardTool wait = binding.extensionRegistry
          .mergedTools()['core.wait']!;
      final ToolResult r = await wait.call(<String, Object?>{'seconds': 99});
      expect(r.ok, isFalse);
      expect(r.error, contains('schema_violation'));
    },
  );

  test(
    'core.wait via the merged tool map completes for an in-range delay',
    () async {
      final LeonardTool wait = binding.extensionRegistry
          .mergedTools()['core.wait']!;
      final ToolResult r = await wait.call(<String, Object?>{'seconds': 0.05});
      expect(r.ok, isTrue, reason: r.error);
    },
  );
}
