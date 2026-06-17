/// Device-free launch target for the `leonard_drive up` e2e.
///
/// `dart run --enable-vm-service` prints the VM-service URI the launcher
/// scrapes; this program installs a pure-Dart `ExplorationHost` exposing one
/// trivial extension and stays alive so an external driver can attach and
/// handshake. No Flutter, no device.
library;

import 'dart:async';
import 'dart:io';

import 'package:leonard_contract/leonard_contract.dart';
import 'package:leonard_host/leonard_host.dart';

Future<void> main() async {
  final ExplorationHost host = ExplorationHost(
    extensions: <LeonardExtension>[_DemoExtension()],
  );
  await host.install();
  // A ready marker for humans reading the teed log; the launcher keys off
  // the VM-service URI line, not this.
  stdout.writeln('LEONARD_TARGET_READY');
  // Keep the event loop (and thus the VM service) alive until killed.
  Timer.periodic(const Duration(seconds: 1), (_) {});
}

class _DemoExtension extends LeonardExtension {
  @override
  String get namespace => 'demo';

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
  String get description => 'Does nothing.';

  @override
  JsonSchema get inputSchema =>
      const JsonSchema(<String, Object?>{'type': 'object'});

  @override
  Future<ToolResult> call(Map<String, Object?> args) async =>
      const ToolResult(ok: true);
}
