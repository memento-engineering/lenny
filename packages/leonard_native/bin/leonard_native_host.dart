/// VM-service host: serves the stateful `native` Leonard extension over
/// `ext.exploration.*` so an external driver (`leonard_cli` / `leonard_drive`)
/// can perceive and drive a native mobile app live — the same surface the
/// Flutter binding and the tmux host expose, but for a native target.
///
/// Run with the VM service enabled against an ALREADY-RUNNING Appium server and
/// an ALREADY-BOOTED iOS simulator (this host boots neither), then point a
/// driver at the printed ws URI:
///
///   dart run --enable-vm-service=0 --disable-service-auth-codes \
///     bin/leonard_native_host.dart --udid SIM_UDID --app /path/to/Runner.app
///
/// Prints `LEONARD_HOST_READY` once installed. SIGTERM/SIGINT dispose the
/// extension (cancelling the watcher + tearing down the device session) and
/// exit cleanly.
//
// This runner is the only `leonard_host`/`leonard_agent` consumer in the
// package; both stay dev_dependencies so the library proper remains
// host-agnostic (m2-spec §2.1). The runner is dev-tooling, so the
// referenced-package lint is suppressed here.
// ignore_for_file: depend_on_referenced_packages
library;

import 'dart:async';
import 'dart:io';

import 'package:leonard_contract/leonard_contract.dart';
import 'package:leonard_host/leonard_host.dart';
import 'package:leonard_native/leonard_native.dart';

Future<void> main(List<String> args) async {
  final Map<String, String> o = _parseArgs(args);
  final String? udid = o['udid'];
  final String? app = o['app'];
  if (udid == null || app == null) {
    stderr.writeln(
      'usage: leonard_native_host --udid <sim-udid> '
      '--app <path-to-.app> [--server <url>] [--platform ios]',
    );
    exit(64);
  }

  final AppiumBackend backend = AppiumBackend(
    server: Uri.parse(o['server'] ?? 'http://127.0.0.1:4723'),
    platform: o['platform'] ?? 'ios',
    udid: udid,
    app: app,
  );
  final NativeExtension ext = NativeExtension(backend);
  final ExplorationHost host = ExplorationHost(
    extensions: <LeonardExtension>[ext],
  );
  await host.install();

  stdout.writeln('LEONARD_HOST_READY');
  await stdout.flush();

  final Completer<void> done = Completer<void>();
  Future<void> shutdown() async {
    try {
      await ext.dispose();
    } on Object {
      // best-effort cleanup
    }
    if (!done.isCompleted) done.complete();
  }

  ProcessSignal.sigterm.watch().listen((_) => unawaited(shutdown()));
  ProcessSignal.sigint.watch().listen((_) => unawaited(shutdown()));

  await done.future;
  exit(0);
}

/// Parses `--key value` pairs from [args] into a map.
Map<String, String> _parseArgs(List<String> args) {
  final Map<String, String> out = <String, String>{};
  for (int i = 0; i < args.length; i++) {
    final String a = args[i];
    if (a.startsWith('--') && i + 1 < args.length) {
      out[a.substring(2)] = args[i + 1];
      i++;
    }
  }
  return out;
}
