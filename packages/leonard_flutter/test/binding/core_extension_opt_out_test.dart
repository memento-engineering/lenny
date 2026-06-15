/// Tests for the `installCoreExtension` opt-out seam on
/// [LeonardBinding.ensureInitialized] (bead lenny-cx6.45).
///
/// When `installCoreExtension: false`, the binding skips constructing and
/// registering the host-owned [CoreExtension], freeing the `core`
/// namespace for a caller-supplied stand-in. This is the seam the
/// agent dogfood harness uses so the loop can exercise the full tool
/// surface (including `core.*`) without booting a real widget tree.
library;

import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class _UserCoreExtension extends LeonardExtension {
  _UserCoreExtension();
  @override
  String get namespace => 'core';
  @override
  List<LeonardTool> get tools => <LeonardTool>[_NoopTool()];
  @override
  Future<void> initialize(ExtensionContext ctx) async {}
  @override
  Future<BusyState> busyState() async => BusyState.idle;
  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}
  @override
  Future<void> dispose() async {}
}

class _NoopTool extends LeonardTool {
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
  tearDown(() async => LeonardBinding.debugReset());

  test('installCoreExtension: false allows a user "core" plugin and omits the '
      'real core tool surface', () async {
    final LeonardBinding binding = LeonardBinding.ensureInitialized(
      extensions: <LeonardExtension>[_UserCoreExtension()],
      installCoreExtension: false,
    )!;
    // Plugin initialization runs in a microtask; flush before
    // inspecting the merged tool map.
    await Future<void>.delayed(Duration.zero);

    final Map<String, LeonardTool> merged = binding.extensionRegistry
        .mergedTools();
    expect(
      merged.keys,
      contains('core.noop'),
      reason: 'user "core" plugin tool must register',
    );
    expect(
      merged.keys,
      isNot(contains('core.tap')),
      reason: 'real CoreExtension tools must NOT be registered',
    );
    expect(
      merged.keys,
      isNot(contains('core.done')),
      reason: 'real CoreExtension tools must NOT be registered',
    );
  });
}
