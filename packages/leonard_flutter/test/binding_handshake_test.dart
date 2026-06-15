import 'dart:convert';
import 'dart:developer' as developer;

import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTool extends LeonardTool {
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

class _FakeExtension extends LeonardExtension {
  @override
  String get namespace => 'router';
  @override
  List<LeonardTool> get tools => const <LeonardTool>[_FakeTool('go')];
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
  // A Flutter binding can only be installed once per process; share a single
  // LeonardBinding across this file's tests (see binding_lifecycle_test).
  late LeonardBinding binding;

  setUpAll(() {
    binding = LeonardBinding.ensureInitialized(
      plugins: <LeonardExtension>[_FakeExtension()],
    )!;
  });

  test('handshake extension is registered exactly once', () {
    expect(kLeonardExtensionPrefix, 'ext.exploration');
    // Re-registering the same name throws -> registration succeeded.
    expect(
      () => developer.registerExtension(
          'ext.exploration.core.handshake',
          (m, p) async => developer.ServiceExtensionResponse.result('{}')),
      throwsArgumentError,
    );
  });

  test('core.handshake payload carries the plugins manifest', () async {
    final String raw = await binding.invokeServiceExtension(
      'ext.exploration.core.handshake',
      const <String, String>{},
    );
    final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
    expect(json['protocolVersion'], '2');
    expect(json['bindingType'], 'LeonardBinding');
    expect(json['flutterMode'], 'debug');
    expect(json['extensionCount'], 1);
    final List<dynamic> plugins = json['extensions'] as List<dynamic>;
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
