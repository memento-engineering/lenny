/// Live end-to-end proof of target-agnostic driving: a real tmux server,
/// served over the VM service by `ExplorationHost` (no Flutter), driven by a
/// `LeonardSession` exactly as `leonard_cli` / `leonard_drive` would.
///
/// Self-skips when tmux is absent; otherwise it spawns the host runner with
/// the VM service enabled, drives new_session + send_keys, and asserts the
/// typed marker shows up in the `tmux` observation fragment.
@Timeout(Duration(seconds: 180))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

bool _tmuxPresent() {
  try {
    return Process.runSync('tmux', const <String>['-V']).exitCode == 0;
  } on Object {
    return false;
  }
}

/// Locate the host runner relative to the current working directory, which
/// differs by invocation: `dart test packages/leonard_tmux` runs from the
/// repo root; `melos exec` runs from the package directory.
String _hostScript() {
  const candidates = <String>[
    'example/tmux_vm_host.dart',
    'packages/leonard_tmux/example/tmux_vm_host.dart',
  ];
  for (final p in candidates) {
    if (File(p).existsSync()) return p;
  }
  throw StateError(
    'cannot locate tmux_vm_host.dart from ${Directory.current.path}',
  );
}

void main() {
  if (!_tmuxPresent()) {
    test(
      'tmux host e2e',
      () {},
      skip: 'tmux not on PATH — live driving e2e skipped',
    );
    return;
  }

  test('drives a live tmux host over the VM service end-to-end', () async {
    const marker = 'LEONARD_E2E_MARKER';
    final label = 'leonard-tmux-e2e-$pid';
    final lines = <String>[];
    final serviceUri = Completer<Uri>();
    final ready = Completer<void>();
    final uriRe = RegExp(r'(http://(?:127\.0\.0\.1|\[::1\]):\d+/\S*)');

    void scan(String line) {
      lines.add(line);
      final m = uriRe.firstMatch(line);
      if (m != null && !serviceUri.isCompleted) {
        serviceUri.complete(Uri.parse(m.group(1)!));
      }
      if (line.contains('LEONARD_HOST_READY') && !ready.isCompleted) {
        ready.complete();
      }
    }

    final proc = await Process.start('dart', <String>[
      'run',
      '--enable-vm-service=0',
      '--disable-service-auth-codes',
      _hostScript(),
      label,
    ]);
    proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(scan);
    proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(scan);

    LeonardSession? session;
    try {
      final httpUri = await serviceUri.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw StateError(
          'no VM service URI from host. child output:\n${lines.join('\n')}',
        ),
      );
      await ready.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw StateError(
          'host never reported ready. child output:\n${lines.join('\n')}',
        ),
      );

      // http://host:port/<token?>/  ->  ws://host:port/<token?>/ws
      final wsUri = httpUri.replace(
        scheme: 'ws',
        pathSegments: <String>[
          ...httpUri.pathSegments.where((s) => s.isNotEmpty),
          'ws',
        ],
      );

      session = await LeonardSession.connect(wsUri);
      await session.start('e2e drive', const LeonardConfig());

      final created = await session.act(<String, dynamic>{
        'name': 'tmux.new_session',
        'args': <String, dynamic>{'name': 'e2e'},
      });
      expect(created['ok'], isTrue, reason: 'new_session: $created');
      final paneId = (created['value'] as Map)['pane'] as String;

      final sent = await session.act(<String, dynamic>{
        'name': 'tmux.send_keys',
        'args': <String, dynamic>{'pane': paneId, 'text': 'echo $marker'},
      });
      expect(sent['ok'], isTrue, reason: 'send_keys: $sent');

      // The tmux fragment is whatever the live snapshot holds; poll the
      // observation until the marker (the typed line / its echo) appears.
      var sawTmux = false;
      var sawMarker = false;
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (DateTime.now().isBefore(deadline)) {
        final obs = await session.observe();
        sawTmux = obs.extensions.containsKey('tmux');
        if (sawTmux && jsonEncode(obs.toJson()).contains(marker)) {
          sawMarker = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      expect(sawTmux, isTrue, reason: 'tmux fragment absent from observation');
      expect(
        sawMarker,
        isTrue,
        reason: 'marker never reached the tmux observation fragment',
      );
    } finally {
      await session?.end();
      proc.kill(ProcessSignal.sigterm);
      try {
        await Process.run('tmux', <String>['-L', label, 'kill-server']);
      } on Object {
        // best-effort
      }
      await proc.exitCode.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          proc.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    }
  });
}
