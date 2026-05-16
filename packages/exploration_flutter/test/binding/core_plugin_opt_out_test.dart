/// Tests for the `installCorePlugin` opt-out seam on
/// [ExplorationBinding.ensureInitialized] (bead lenny-cx6.45).
///
/// When `installCorePlugin: false`, the binding skips constructing and
/// registering the host-owned [CorePlugin], freeing the `core`
/// namespace for a caller-supplied stand-in. This is the seam the
/// agent dogfood harness uses so the loop can exercise the full tool
/// surface (including `core.*`) without booting a real widget tree.
library;

import 'package:exploration_flutter/contract.dart';
import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class _UserCorePlugin extends ExplorationPlugin {
  _UserCorePlugin();
  @override
  String get namespace => 'core';
  @override
  List<ExplorationTool> get tools => <ExplorationTool>[_NoopTool()];
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

class _NoopTool extends ExplorationTool {
  @override
  String get name => 'noop';
  @override
  String get description => 'test stand-in';
  @override
  JsonSchema get inputSchema =>
      const JsonSchema(<String, Object?>{'type': 'object'});
  @override
  Future<ToolResult> call(Map<String, Object?> args) async =>
      ToolResult(ok: true, value: args);
}

void main() {
  tearDown(() async => ExplorationBinding.debugReset());

  test(
    'installCorePlugin: false allows a user "core" plugin and omits the '
    'real core tool surface',
    () async {
      final ExplorationBinding binding = ExplorationBinding.ensureInitialized(
        plugins: <ExplorationPlugin>[_UserCorePlugin()],
        installCorePlugin: false,
      )!;
      // Plugin initialization runs in a microtask; flush before
      // inspecting the merged tool map.
      await Future<void>.delayed(Duration.zero);

      final Map<String, ExplorationTool> merged =
          binding.pluginRegistry.mergedTools();
      expect(merged.keys, contains('core.noop'),
          reason: 'user "core" plugin tool must register');
      expect(merged.keys, isNot(contains('core.tap')),
          reason: 'real CorePlugin tools must NOT be registered');
      expect(merged.keys, isNot(contains('core.done')),
          reason: 'real CorePlugin tools must NOT be registered');
    },
  );
}
