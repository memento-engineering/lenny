library;

import 'dart:convert';

import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class _EchoTool extends LeonardTool {
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

class _EchoExtension extends LeonardExtension {
  @override
  String get namespace => 'testplugin';

  @override
  List<LeonardTool> get tools => [_EchoTool()];

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
    binding = LeonardBinding.ensureInitialized(plugins: [_EchoExtension()])!;
    // initializeAll runs in a microtask; flush it and the chained
    // _registerExtensionToolExtensions call before asserting.
    await Future<void>.delayed(Duration.zero);
  });

  tearDownAll(() async => LeonardBinding.debugReset());

  test(
    'ext.exploration.testplugin.echo is in _extensionCallbacks '
    '(proves real _registerExtension path, not invokeExtensionTool bypass)',
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
    '(CoreExtension tools registered by binding-level loop)',
    () {
      expect(
        binding.debugHasRegisteredExtension(
            'ext.exploration.core.tap'),
        isTrue,
      );
    },
  );

  test(
    'invokeServiceExtension dispatches testplugin.echo without invokeExtensionTool',
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
