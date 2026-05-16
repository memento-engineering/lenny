/// Regression test for lenny-cx6.46.
///
/// Proves that [BindingVmServiceFake] routes by
/// `pluginRegistry.mergedTools()` and not by the literal
/// `ext.flutter.exploration.core.*` URL prefix:
///
///   - a plugin registered under namespace `core` (deliberately
///     reusing the namespace that previously triggered the routing
///     bug) is reached via `invokePluginTool`;
///   - a binding-owned extension (`core.get_stable_observation`),
///     which is NOT in `mergedTools()`, falls through to
///     `invokeServiceExtension`;
///   - any method that does not start with
///     `ext.flutter.exploration.` still throws
///     `RPCError(..., -32601, ...)`.
library;

import 'package:exploration_flutter/contract.dart';
import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart';

import 'binding_vm_service_fake.dart';

class _CoreNamespaceTapTool extends ExplorationTool {
  _CoreNamespaceTapTool();

  bool invoked = false;
  Map<String, Object?>? lastArgs;

  @override
  String get name => 'tap';

  @override
  String get description => 'core.tap stand-in for routing regression';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'x': <String, Object?>{'type': 'number'},
          'y': <String, Object?>{'type': 'number'},
        },
      });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    invoked = true;
    lastArgs = Map<String, Object?>.from(args);
    return const ToolResult(ok: true, value: 'tapped');
  }
}

class _CoreNamespacePlugin extends ExplorationPlugin {
  _CoreNamespacePlugin(this.tap);

  final _CoreNamespaceTapTool tap;

  @override
  String get namespace => 'core';

  @override
  List<ExplorationTool> get tools => <ExplorationTool>[tap];

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
  late _CoreNamespaceTapTool tap;
  late BindingVmServiceFake fake;

  setUpAll(() async {
    tap = _CoreNamespaceTapTool();
    binding = ExplorationBinding.ensureInitialized(
      plugins: <ExplorationPlugin>[_CoreNamespacePlugin(tap)],
      installCorePlugin: false,
    )!;
    // Plugin initialization runs in a microtask; flush it so the merged
    // tool map is populated before the fake's first lookup.
    await Future<void>.delayed(Duration.zero);
    // PolicyLoop awaits `SchedulerBinding.endOfFrame`; this test runs
    // as a plain `test()` with no widget pumping, so inject a no-op
    // frame-wait and a static wall-clock to let the binding-owned
    // `core.get_stable_observation` path terminate without scheduling
    // frames the host will never drive.
    int now = 0;
    binding.debugSetPolicyLoopSeamsForTesting(
      waitForFrame: () async {
        now += 16;
      },
      nowMs: () => now,
    );
    fake = BindingVmServiceFake(binding);
  });

  tearDownAll(() async {
    await fake.dispose();
    await ExplorationBinding.debugReset();
  });

  test(
    'core.tap routes via pluginRegistry.mergedTools -> invokePluginTool',
    () async {
      final Response r = await fake.callServiceExtension(
        'ext.flutter.exploration.core.tap',
        args: <String, dynamic>{'x': 0.1, 'y': 0.2},
      );
      expect(tap.invoked, isTrue,
          reason: 'plugin tool must be reached when its <ns>.<tool> '
              'suffix is in mergedTools()');
      expect(tap.lastArgs, <String, Object?>{'x': 0.1, 'y': 0.2});
      expect(r.json!['ok'], isTrue);
      expect(r.json!['value'], 'tapped');
    },
  );

  test(
    'core.get_stable_observation (binding-owned, not in mergedTools) '
    'falls through to invokeServiceExtension',
    () async {
      final Response r = await fake.callServiceExtension(
        'ext.flutter.exploration.core.get_stable_observation',
      );
      // The binding-owned extension wraps the result in
      // `{type: 'Observation', value: <bundle>}`; the plugin envelope
      // would have shape `{ok, value, error}`. Asserting on `type`
      // proves we reached `invokeServiceExtension`, not
      // `invokePluginTool`.
      expect(r.json!['type'], 'Observation',
          reason: 'binding-owned observation envelope must come from '
              'invokeServiceExtension, not the plugin path');
      expect(r.json!.containsKey('value'), isTrue);
    },
  );

  test('unknown prefix throws RPCError -32601', () async {
    expect(
      () => fake.callServiceExtension('ext.dart.io.read'),
      throwsA(isA<RPCError>().having(
        (RPCError e) => e.code,
        'code',
        -32601,
      )),
    );
  });
}
