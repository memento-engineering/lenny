import 'dart:convert';
import 'dart:developer' as developer;

import 'package:exploration_flutter/contract.dart';
import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTool extends ExplorationTool {
  const _FakeTool(this.name);
  @override
  final String name;
  @override
  String get description => 'fake';
  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
        'type': 'object',
      });
  @override
  Future<ToolResult> call(Map<String, Object?> args) async =>
      const ToolResult(ok: true);
}

class _FakePlugin extends ExplorationPlugin {
  @override
  String get namespace => 'router';
  @override
  List<ExplorationTool> get tools => const <ExplorationTool>[_FakeTool('go')];
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
  // A Flutter binding can only be installed once per process; share a single
  // ExplorationBinding across this file's tests (see binding_lifecycle_test).
  late ExplorationBinding binding;

  setUpAll(() {
    binding = ExplorationBinding.ensureInitialized(
      plugins: <ExplorationPlugin>[_FakePlugin()],
    )!;
  });

  test('handshake extension is registered exactly once', () {
    expect(kExplorationExtensionPrefix, 'ext.flutter.exploration');
    // Re-registering the same name throws -> registration succeeded.
    expect(
      () => developer.registerExtension(
          'ext.flutter.exploration.core.handshake',
          (m, p) async => developer.ServiceExtensionResponse.result('{}')),
      throwsArgumentError,
    );
  });

  test('core.handshake payload carries the plugins manifest', () async {
    final String raw = await binding.invokeServiceExtension(
      'ext.flutter.exploration.core.handshake',
      const <String, String>{},
    );
    final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
    expect(json['protocolVersion'], '1');
    expect(json['bindingType'], 'ExplorationBinding');
    expect(json['flutterMode'], 'debug');
    expect(json['pluginCount'], 1);
    final List<dynamic> plugins = json['plugins'] as List<dynamic>;
    final Map<String, List<String>> byNs = <String, List<String>>{
      for (final dynamic p in plugins)
        (p as Map)['namespace'] as String:
            (p['tools'] as List).cast<String>(),
    };
    expect(byNs.keys, containsAll(<String>['core', 'router']));
    expect(byNs['router'], <String>['go']);
    expect(byNs['core'], contains('tap'));
    expect(byNs['core'], contains('done'));
    // bare tokens — no namespacing
    expect(byNs['router']!.every((String t) => !t.contains('.')), isTrue);
  });
}
