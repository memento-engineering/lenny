/// Live proof of the `tmux` Leonard extension against a real tmux server.
///
/// Self-skips when tmux is absent. Runs on an isolated `-L` socket and kills
/// its own server on exit, so it never touches your default tmux.
///
///   dart run example/main.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:genesis_tmux/genesis_tmux.dart';
import 'package:leonard_agent/leonard_agent.dart' show ExtensionFragment;
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
  final tmux = TmuxExtension(client);

  try {
    final created = await tmux.executeAction('tmux.new_session', {
      'name': 'demo',
    });
    final paneId = created['pane'] as String;
    stdout.writeln('created session "demo" -> pane $paneId\n');

    stdout.writeln('=== observation 1 (fresh session) ===');
    _printFragment(await tmux.observe());

    stdout.writeln('\n>> tmux.send_keys: echo leonard-was-here');
    final sent = await tmux.executeAction('tmux.send_keys', {
      'pane': paneId,
      'text': 'echo leonard-was-here',
    });
    stdout.writeln('   $sent');
    await _waitForOutput(client, paneId, 'leonard-was-here');

    stdout.writeln('\n=== observation 2 (after send_keys) ===');
    _printFragment(await tmux.observe());

    stdout.writeln(
      '\ntools contributed: ${tmux.tools.map((t) => t.name).toList()}',
    );
  } finally {
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

void _printFragment(ExtensionFragment fragment) {
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(fragment.toJson()));
}

/// Polls the pane until [marker] appears (output is async), bounded.
Future<void> _waitForOutput(
  TmuxClient client,
  String paneId,
  String marker, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if ((await client.capturePane(paneId, lines: 50)).contains(marker)) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
