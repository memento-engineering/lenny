library;

import 'dart:convert';

import 'package:exploration_flutter/contract.dart';
import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class _EchoTool extends ExplorationTool {
  @override
  String get name => 'echo';

  @override
  String get description => 'echo';

  @override
  JsonSchema get inputSchema => const JsonSchema({'type': 'object'});

  @override
  Future<ToolResult> call(Map<String, Object?> args) async =>
      ToolResult(ok: true, value: args['text']);
}

class _EchoPlugin extends ExplorationPlugin {
  @override
  String get namespace => 'testplugin';

  @override
  List<ExplorationTool> get tools => [_EchoTool()];

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
    binding = ExplorationBinding.ensureInitialized(plugins: [_EchoPlugin()])!;
    // initializeAll runs in a microtask; flush it and the chained
    // _registerPluginToolExtensions call before asserting.
    await Future<void>.delayed(Duration.zero);
  });

  tearDownAll(() async => ExplorationBinding.debugReset());

  test(
    'ext.exploration.testplugin.echo is in _extensionCallbacks '
    '(proves real _registerExtension path, not invokePluginTool bypass)',
    () {
      expect(
        binding.debugHasRegisteredExtension(
            'ext.exploration.testplugin.echo'),
        isTrue,
        reason: 'plugin tool must be registered via _registerExtension '
            'so _extensionCallbacks is populated',
      );
    },
  );

  test(
    'ext.exploration.core.tap is in _extensionCallbacks '
    '(CorePlugin tools registered by binding-level loop)',
    () {
      expect(
        binding.debugHasRegisteredExtension(
            'ext.exploration.core.tap'),
        isTrue,
      );
    },
  );

  test(
    'invokeServiceExtension dispatches testplugin.echo without invokePluginTool',
    () async {
      final String raw = await binding.invokeServiceExtension(
        'ext.exploration.testplugin.echo',
        {'text': jsonEncode('hello')},
      );
      final Map<String, dynamic> envelope =
          jsonDecode(raw) as Map<String, dynamic>;
      expect(envelope['ok'], isTrue);
      expect(envelope['value'], 'hello');
    },
  );
}
