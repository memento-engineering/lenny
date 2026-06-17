/// VM-service host: serves the stateful `tmux` Leonard extension over
/// `ext.exploration.*` so an external driver (`leonard_cli` / `leonard_drive`)
/// can perceive and drive a tmux server live — the same surface the Flutter
/// binding exposes, but for a non-Flutter target.
///
/// Run with the VM service enabled, then point a driver at the printed ws URI:
///
///   dart run --enable-vm-service=0 --disable-service-auth-codes \
///     example/tmux_vm_host.dart [socket-label]
///
/// Prints `LEONARD_HOST_READY socket=<label>` once installed. SIGTERM/SIGINT
/// kill the isolated tmux server and exit cleanly.
library;

import 'dart:async';
import 'dart:io';

import 'package:genesis_tmux/genesis_tmux.dart';
import 'package:leonard_contract/leonard_contract.dart';
import 'package:leonard_host/leonard_host.dart';
import 'package:leonard_tmux/leonard_tmux.dart';

Future<void> main(List<String> args) async {
  final label = args.isNotEmpty ? args.first : 'leonard-tmux-host-$pid';
  final client = TmuxClient(
    executor: const ProcessTmuxExecutor(),
    socket: TmuxSocket.named(label),
  );
  final ext = TmuxExtension(client);
  final host = ExplorationHost(extensions: <LeonardExtension>[ext]);
  await host.install();

  stdout.writeln('LEONARD_HOST_READY socket=$label');
  await stdout.flush();

  final done = Completer<void>();
  Future<void> shutdown() async {
    try {
      await ext.dispose();
      await client.killServer();
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
