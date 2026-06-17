/// `leonard_drive` — a thin, stateless VM-service driver so an EXTERNAL
/// agent (e.g. Claude Code) can be the brain: observe the app, decide,
/// invoke a tool, repeat. Unlike `leonard_cli` (which runs lenny's own
/// autonomous LLM loop), this command makes NO model calls — each
/// invocation connects, performs one operation, prints JSON, disconnects.
///
/// Subcommands (all require `--vm-uri ws://…/ws`):
///
///   tools    — handshake; print the available tool manifest
///              { contract_version, namespaces: [ {namespace, tools:[…]} ],
///                capabilities: [ … ] }. `capabilities` lists reachable
///                host features that are NOT namespaced tools — notably
///                `screenshot` (use the `screenshot` subcommand), which is
///                absent from `namespaces` by design.
///   observe  — print the current stable observation as JSON; `--policy`
///              selects the stability policy (default action-relative).
///   invoke   — call one tool: `--tool core.tap --args '{"node_id":5}'`;
///              prints the tool result { ok, value | error }.
///   screenshot — capture a still: decode `core.screenshot` and write the PNG
///              to `--out path.png`; prints { out, width_px, height_px,
///              device_pixel_ratio }. Debug/profile builds only. Just pixels —
///              no settle, no golden compare (the caller owns those).
///   up       — boot a target and HOLD it: `--runner flutter|dart`,
///              `-t <entrypoint>` (`-d <device>` for flutter), discover the
///              VM-service URI, print { event:"vm_service_ready", ws_uri, … }
///              and optionally write `--uri-file`/`--pid-file`, then keep the
///              app alive until a signal (or `down`). The external brain then
///              attaches stateless `observe`/`invoke`/`screenshot` calls to
///              `ws_uri`. No model, no goal, no loop — it just hands off.
///   down     — stop a target started by `up`: signal the pid in `--pid-file`.
///
/// Statelessness: every call opens a fresh VM-service session and runs
/// the handshake (which resets the per-session terminal latch), so the
/// external brain owns all turn state. Each `observe` returns the FULL
/// current observation — the brain compares turns itself; there is no
/// server-side diff (that is the autonomous loop's optimization).
///
/// Exit codes: 0 ok · 64 usage error · 1 runtime/connection error. All
/// machine output goes to stdout as a single JSON object; diagnostics go
/// to stderr.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:leonard_agent/leonard_agent.dart';
import 'package:leonard_cli/src/launcher.dart';

Future<void> main(List<String> argv) async {
  exitCode = await _run(argv);
}

const String _placeholderGoal = 'external-driver';

StabilityPolicy _policy(String name) => switch (name) {
  'idle' => StabilityPolicy.quietFrame,
  'frame-stable' => StabilityPolicy.boundedStability,
  'action-relative' => StabilityPolicy.actionRelative,
  _ => throw const FormatException('invalid --policy'),
};

ArgParser _parser() => ArgParser()
  ..addOption('vm-uri', help: 'Flutter VM service ws:// URI (required).')
  ..addOption(
    'policy',
    defaultsTo: 'action-relative',
    allowed: <String>['idle', 'frame-stable', 'action-relative'],
    help: 'Stability policy for observe.',
  )
  ..addOption('tool', help: 'Fully-qualified tool name, e.g. core.tap.')
  ..addOption('args', help: 'JSON object of tool arguments (default {}).')
  ..addOption('out', help: 'screenshot: file path to write the PNG to.')
  ..addOption(
    'runner',
    defaultsTo: 'flutter',
    allowed: <String>['flutter', 'dart'],
    help: 'up: how to boot the target (flutter run | dart run).',
  )
  ..addOption(
    'device',
    abbr: 'd',
    help: 'up: Flutter device id (flutter runner only).',
  )
  ..addOption('target', abbr: 't', help: 'up: entrypoint Dart file to run.')
  ..addOption(
    'uri-file',
    help: 'up: also write the discovered ws:// URI to this path.',
  )
  ..addOption(
    'pid-file',
    help:
        'up: write this process\'s pid here (down reads it to stop the '
        'target). down: the pid-file to signal.',
  )
  ..addOption(
    'timeout',
    defaultsTo: '180',
    help: 'up: seconds to wait for the VM service URI (default 180).',
  )
  ..addFlag('help', abbr: 'h', negatable: false);

Future<int> _run(List<String> argv) async {
  if (argv.isEmpty || argv.contains('-h') || argv.contains('--help')) {
    _usage(stdout);
    return argv.isEmpty ? 64 : 0;
  }
  final String command = argv.first;
  if (!const <String>{
    'tools',
    'observe',
    'invoke',
    'screenshot',
    'up',
    'down',
  }.contains(command)) {
    stderr.writeln('error: unknown command "$command"');
    _usage(stderr);
    return 64;
  }

  final ArgResults res;
  try {
    res = _parser().parse(argv.sublist(1));
  } on FormatException catch (e) {
    stderr.writeln('error: ${e.message}');
    return 64;
  }

  // up/down own the target's lifecycle and take no --vm-uri (up mints one;
  // down signals an existing up). Dispatch before the vm-uri gate below.
  if (command == 'up') return _up(res);
  if (command == 'down') return _down(res);

  final String? rawUri = res['vm-uri'] as String?;
  final Uri? vmUri = rawUri == null ? null : Uri.tryParse(rawUri);
  if (vmUri == null || (!vmUri.isScheme('ws') && !vmUri.isScheme('wss'))) {
    stderr.writeln('error: --vm-uri must be a ws:// or wss:// URI');
    return 64;
  }

  final String? outPath = res['out'] as String?;
  if (command == 'screenshot' && (outPath == null || outPath.isEmpty)) {
    stderr.writeln('error: screenshot requires --out <path.png>');
    return 64;
  }

  LeonardSession? session;
  try {
    session = await LeonardSession.connect(vmUri);
    // start() runs the handshake (and resets the terminal latch), priming
    // the session for observe/act. The goal is only stamped on an event.
    await session.start(_placeholderGoal, const LeonardConfig());

    switch (command) {
      case 'tools':
        _emit(<String, dynamic>{
          'contract_version': session.handshake.contractVersion,
          'namespaces': <Map<String, dynamic>>[
            for (final ExtensionManifestEntry e in session.handshake.extensions)
              <String, dynamic>{'namespace': e.namespace, 'tools': e.tools},
          ],
          // Reachable host capabilities that are NOT namespaced tools (so they
          // are absent from `namespaces`). `screenshot` here means the
          // `screenshot --out <path.png>` subcommand works against this target.
          'capabilities': session.handshake.capabilities,
        });
        return 0;

      case 'observe':
        final StabilityPolicy policy = _policy(res['policy'] as String);
        final Observation curr = await session.observe(policy: policy);
        _emit(<String, dynamic>{'observation': curr.toJson()});
        return 0;

      case 'invoke':
        final String? tool = res['tool'] as String?;
        if (tool == null || tool.isEmpty) {
          stderr.writeln('error: invoke requires --tool <namespace.tool>');
          return 64;
        }
        final Map<String, dynamic> args;
        try {
          final String raw = (res['args'] as String?) ?? '{}';
          final Object? decoded = jsonDecode(raw.isEmpty ? '{}' : raw);
          if (decoded is! Map) {
            stderr.writeln('error: --args must be a JSON object');
            return 64;
          }
          args = decoded.cast<String, dynamic>();
        } on FormatException catch (e) {
          stderr.writeln('error: --args is not valid JSON: ${e.message}');
          return 64;
        }
        final Map<String, dynamic> result = await session.act(<String, dynamic>{
          'name': tool,
          'args': args,
        });
        _emit(<String, dynamic>{'tool': tool, 'result': result});
        return 0;

      case 'screenshot':
        // core.screenshot is a raw VM extension (not a manifest tool);
        // executeAction routes `core.screenshot` ->
        // ext.exploration.core.screenshot, whose body is
        // { result: { png_base64, width_px, height_px, device_pixel_ratio } }.
        final Map<String, dynamic> shot = await session.act(<String, dynamic>{
          'name': 'core.screenshot',
          'args': <String, dynamic>{},
        });
        final Object? inner = shot['result'];
        if (inner is! Map) {
          stderr.writeln('error: screenshot unavailable (no result payload)');
          return 1;
        }
        final Object? b64 = inner['png_base64'];
        if (b64 is! String || b64.isEmpty) {
          stderr.writeln('error: screenshot unavailable (no png_base64)');
          return 1;
        }
        final File outFile = File(outPath!);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(base64Decode(b64), flush: true);
        _emit(<String, dynamic>{
          'out': outFile.path,
          'width_px': inner['width_px'],
          'height_px': inner['height_px'],
          'device_pixel_ratio': inner['device_pixel_ratio'],
        });
        return 0;
    }
    return 0;
  } on Object catch (e) {
    stderr.writeln('error: $e');
    return 1;
  } finally {
    await session?.end();
  }
}

/// `up` — boot a target, discover its VM-service ws:// URI, emit it
/// machine-readably, then HOLD the process alive (teeing its log to stderr)
/// until a signal or the target exits. No model, no goal, no loop: the
/// caller is the brain (stateless observe/invoke calls attach fresh each
/// time), so this just guarantees a live target + a known URI, then gets
/// out of the way.
Future<int> _up(ArgResults res) async {
  final String? target = res['target'] as String?;
  if (target == null || target.isEmpty) {
    stderr.writeln('error: up requires --target <entrypoint.dart>');
    return 64;
  }
  final TargetRunner runner = switch (res['runner'] as String) {
    'flutter' => TargetRunner.flutter,
    'dart' => TargetRunner.dart,
    _ => TargetRunner.flutter,
  };
  final String? device = res['device'] as String?;
  // "No dual mode": a meaningless combination is a hard error, not a
  // silent mode switch.
  if (runner == TargetRunner.dart && device != null && device.isNotEmpty) {
    stderr.writeln(
      'error: --device is meaningless with --runner dart; drop -d',
    );
    return 64;
  }
  final int? timeoutSecs = int.tryParse(res['timeout'] as String? ?? '180');
  if (timeoutSecs == null || timeoutSecs <= 0) {
    stderr.writeln('error: --timeout must be a positive integer (seconds)');
    return 64;
  }

  final LaunchHandle handle;
  try {
    handle = await launchTarget(
      runner: runner,
      entrypoint: target,
      device: device,
      onLog: stderr.writeln,
      timeout: Duration(seconds: timeoutSecs),
    );
  } on TimeoutException {
    stderr.writeln(
      'error: no VM service URI within ${timeoutSecs}s; gave up booting target',
    );
    return 1;
  } on ArgumentError catch (e) {
    stderr.writeln('error: ${e.message}');
    return 64;
  } on Object catch (e) {
    stderr.writeln('error: launch failed: $e');
    return 1;
  }

  // Machine-readable handoff: a single stable JSON line on stdout. The
  // external brain captures `ws_uri` from here (or from --uri-file) — no
  // log-grepping, no http->ws conversion.
  _emit(<String, dynamic>{
    'event': 'vm_service_ready',
    'ws_uri': handle.wsUri.toString(),
    'runner': runner.name,
    'pid': handle.process.pid,
  });

  final String? uriFile = res['uri-file'] as String?;
  if (uriFile != null && uriFile.isNotEmpty) {
    final File f = File(uriFile);
    await f.parent.create(recursive: true);
    await f.writeAsString('${handle.wsUri}\n', flush: true);
  }
  final String? pidFile = res['pid-file'] as String?;
  if (pidFile != null && pidFile.isNotEmpty) {
    // This process's own pid: `down` signals it, and its handler tears the
    // target down cleanly (cleaner than killing the child out from under us).
    final File f = File(pidFile);
    await f.parent.create(recursive: true);
    await f.writeAsString('$pid\n', flush: true);
  }

  // Hold until a signal or the target exits.
  final Completer<int> done = Completer<int>();
  Future<void> tearDown(String why) async {
    if (done.isCompleted) return;
    stderr.writeln('info: $why; shutting down target…');
    await handle.shutdown();
    if (!done.isCompleted) done.complete(0);
  }

  final StreamSubscription<ProcessSignal> sigint = ProcessSignal.sigint
      .watch()
      .listen((_) => tearDown('received SIGINT'));
  StreamSubscription<ProcessSignal>? sigterm;
  try {
    sigterm = ProcessSignal.sigterm.watch().listen(
      (_) => tearDown('received SIGTERM'),
    );
  } on Object {
    // SIGTERM is not watchable on every platform (e.g. Windows); SIGINT
    // and target-exit still terminate the hold.
  }
  unawaited(
    handle.exitCode.then((int code) {
      if (!done.isCompleted) {
        stderr.writeln('info: target exited (code $code)');
        done.complete(0);
      }
    }),
  );

  final int code = await done.future;
  await sigint.cancel();
  await sigterm?.cancel();
  if (pidFile != null && pidFile.isNotEmpty) {
    try {
      final File f = File(pidFile);
      if (f.existsSync()) await f.delete();
    } on Object {
      // best-effort cleanup
    }
  }
  _emit(<String, dynamic>{'event': 'shutdown'});
  return code;
}

/// `down` — stop a target started by `up`, by signalling the `up` process
/// recorded in its --pid-file (whose handler tears the target down cleanly).
Future<int> _down(ArgResults res) async {
  final String? pidFile = res['pid-file'] as String?;
  if (pidFile == null || pidFile.isEmpty) {
    stderr.writeln('error: down requires --pid-file <path> (written by up)');
    return 64;
  }
  final File f = File(pidFile);
  if (!f.existsSync()) {
    stderr.writeln('error: pid-file not found: $pidFile');
    return 1;
  }
  final int? targetPid = int.tryParse((await f.readAsString()).trim());
  if (targetPid == null) {
    stderr.writeln('error: pid-file holds no pid: $pidFile');
    return 1;
  }
  final bool ok = Process.killPid(targetPid, ProcessSignal.sigterm);
  _emit(<String, dynamic>{'event': 'down', 'pid': targetPid, 'signalled': ok});
  return ok ? 0 : 1;
}

void _emit(Map<String, dynamic> obj) =>
    stdout.writeln(const JsonEncoder().convert(obj));

void _usage(IOSink out) {
  out.writeln(
    'Usage: leonard_drive <tools|observe|invoke|screenshot|up|down> [...]',
  );
  out.writeln();
  out.writeln('  tools       --vm-uri <ws>');
  out.writeln('  observe     --vm-uri <ws> [--policy P]');
  out.writeln(
    '  invoke      --vm-uri <ws> --tool core.tap --args \'{"node_id":5}\'',
  );
  out.writeln('  screenshot  --vm-uri <ws> --out path.png');
  out.writeln(
    '  up          --runner flutter -d <device> -t <entry> [--uri-file F] '
    '[--pid-file P]',
  );
  out.writeln('  up          --runner dart -t <entry> [--uri-file F]');
  out.writeln('  down        --pid-file P');
  out.writeln();
  out.writeln(_parser().usage);
}
