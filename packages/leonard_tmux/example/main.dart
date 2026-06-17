/// Live proof of the stateful `tmux` Leonard *contract* extension, in-process.
///
/// Self-skips when tmux is absent. Runs on an isolated `-L` socket and kills
/// its own server on exit, so it never touches your default tmux.
///
///   dart run example/main.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:genesis_perception/genesis_perception.dart';
import 'package:genesis_tmux/genesis_tmux.dart';
import 'package:leonard_contract/leonard_contract.dart';
import 'package:leonard_tmux/leonard_tmux.dart';

Future<void> main() async {
  if (!_tmuxPresent()) {
    stdout.writeln('tmux not found on PATH — skipping the live demo.');
    return;
  }

  final socket = TmuxSocket.named('leonard-tmux-demo-$pid');
  final client = TmuxClient(
    executor: const ProcessTmuxExecutor(),
    socket: socket,
  );
  final ext = TmuxExtension(client);

  try {
    // initialize() starts the watcher and seeds the first live snapshot.
    await ext.initialize(ExtensionContext(namespace: 'tmux'));

    final newSession = ext.tools.firstWhere((t) => t.name == 'new_session');
    final created = await newSession.call(<String, Object?>{'name': 'demo'});
    final paneId = (created.value! as Map)['pane'] as String;
    stdout.writeln('created session "demo" -> pane $paneId\n');

    stdout.writeln('=== observation 1 (fresh session) ===');
    _printFragment(ext);

    final sendKeys = ext.tools.firstWhere((t) => t.name == 'send_keys');
    stdout.writeln('\n>> send_keys: echo leonard-was-here');
    await sendKeys.call(<String, Object?>{
      'pane': paneId,
      'text': 'echo leonard-was-here',
    });
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await ext.refreshNow();

    stdout.writeln('\n=== observation 2 (after send_keys) ===');
    _printFragment(ext);

    stdout.writeln(
      '\ntools contributed: ${ext.tools.map((t) => t.name).toList()}',
    );
  } finally {
    await ext.dispose();
    await client.killServer();
    stdout.writeln(
      '\nkilled the demo server; socket ${socket.label} is clean.',
    );
  }
}

bool _tmuxPresent() {
  try {
    return Process.runSync('tmux', ['-V']).exitCode == 0;
  } on Object {
    return false;
  }
}

void _printFragment(TmuxExtension ext) {
  final owner = PerceptionOwner();
  final root = owner.mountRoot(ext.buildPerception());
  final data = serializePerceptionFragment(root);
  owner.unmountRoot();
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(data));
}
