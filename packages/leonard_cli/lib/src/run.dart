/// Top-level CLI entrypoint composed by `bin/leonard_cli.dart`.
///
/// Parses argv, opens the trajectory file, builds a model provider,
/// connects an [LeonardSession], and drives the perception-action
/// loop via [LeonardSession.run] (which constructs a [LoopDriver]
/// on top of a caller-supplied [DefaultLoopHost]).
library;

import 'dart:async';
import 'dart:io';

import 'package:leonard_agent/leonard_agent.dart';

import 'cli_args.dart';
import 'file_trajectory_sink.dart';
import 'extension_tools.dart';
import 'provider_factory.dart';

/// Path the CLI advertises in `--help` for the bundled AGENTS.md.
const String kAgentsMdRelativePath = 'leonard_cli/templates/AGENTS.md';

/// Harness version stamped into the trajectory header. Bump when the
/// CLI emits a record-shape change consumers need to detect.
const String _kHarnessVersion = '0.5.0';

/// Run the CLI end-to-end. Returns the process exit code:
///   * 0  — clean session (any non-error termination)
///   * 64 — usage error (Unix convention)
///   * 1  — harness error (`agent_stuck`, `connection_lost`, etc.)
Future<int> runCli(
  List<String> argv, {
  required Stdin stdin,
  required Stdout stdout,
  required IOSink stderr,
}) async {
  // ----- --help short-circuit ----------------------------------------
  if (argv.contains('-h') || argv.contains('--help')) {
    stdout.writeln('Usage: leonard_cli [options]');
    stdout.writeln();
    stdout.writeln(buildParser().usage);
    stdout.writeln();
    stdout.writeln('AGENTS.md template: $kAgentsMdRelativePath');
    return 0;
  }

  // ----- parse argv --------------------------------------------------
  final CliArgs args;
  try {
    args = parseCliArgs(argv);
  } on CliUsageError catch (e) {
    stderr.writeln('error: ${e.message}');
    stderr.writeln(buildParser().usage);
    return 64;
  }

  // ----- resolve goal (flag wins, stdin fallback) --------------------
  String? goal = args.goal;
  if (goal == null) {
    if (stdin.hasTerminal) {
      stderr.writeln(
        'error: --goal not provided and stdin is a TTY (nothing to read)',
      );
      stderr.writeln(buildParser().usage);
      return 64;
    }
    goal = (await stdin.transform(systemEncoding.decoder).join()).trim();
    if (goal.isEmpty) {
      stderr.writeln('error: empty goal (provide --goal or pipe a goal)');
      return 64;
    }
  }

  // ----- open trajectory sink ---------------------------------------
  final String outPath = args.outputPath ?? FileTrajectorySink.defaultOutputPath();
  final FileTrajectorySink sink = await FileTrajectorySink.open(outPath);
  final TrajectoryWriter writer = TrajectoryWriter(sink);

  // ----- build provider (may throw on missing API key) --------------
  // Mint a per-run sessionId so the qwen-mlx tier can stamp every
  // request with X-Session-Id and an `leonard-<sessionId>-<ms>`
  // X-Conversation-Id (mirrors fs agent's `fsagent-<beadID>-<unixtime>`
  // convention). Slug ISO-8601 to keep the value safe for HTTP headers.
  final String sessionId =
      'cli-${DateTime.now().toUtc().toIso8601String()}'
          .replaceAll(RegExp(r'[^A-Za-z0-9-]'), '-');
  final ModelProvider provider;
  try {
    provider = buildProvider(
      args.tier,
      sessionId: sessionId,
      onModelDiagnostics: (Map<String, Object?> d) {
        final StringBuffer line = StringBuffer('[model] ')
          ..write('${d['provider']} ${d['model']} ')
          ..write('http=${d['http_status']} dur=${d['duration_ms']}ms ')
          ..write('stop=${d['stop_reason']} tool_use=${d['tool_use']} ')
          ..write('ok=${d['ok']}');
        if (d['error'] != null) line.write(' error=${d['error']}');
        stderr.writeln(line);
      },
    );
  } on StateError catch (e) {
    stderr.writeln('error: ${e.message}');
    await writer.close(SessionFooter(
      outcome: SessionOutcome.harnessError,
      totalTurns: 0,
      totalDurationMs: 0,
      harnessError: 'config_error',
    ));
    return 1;
  }

  // ----- connect session --------------------------------------------
  final LeonardSession session;
  try {
    session = await LeonardSession.connect(args.vmUri);
  } on Object catch (e) {
    stderr.writeln('error: failed to connect to ${args.vmUri}: $e');
    await writer.close(SessionFooter(
      outcome: SessionOutcome.harnessError,
      totalTurns: 0,
      totalDurationMs: 0,
      harnessError: 'connection_lost',
    ));
    return 1;
  }

  // ----- progress renderer ------------------------------------------
  final StreamSubscription<SessionProgressEvent> sub =
      session.progress.listen((e) => _render(stdout, e));

  try {
    // ----- start session --------------------------------------------
    await session.start(goal, const LeonardConfig());

    // ----- extension warning block (unchanged) ----------------------------------
    final List<String> unknown = unknownExtensionNamespaces(
      requested: args.extensions,
      handshake: session.handshake.plugins,
    );
    for (final String ns in unknown) {
      stderr.writeln(
        'warning: --extensions includes "$ns" but the binding did not '
        'report an extension with that namespace; ignoring.',
      );
    }
    // 'core' is unconditionally projected so the model always has action tools.
    // unknownExtensionNamespaces still uses args.extensions (no 'core' warning).
    final Map<String, List<ToolDescriptor>> extensionTools = buildExtensionTools(
      requested: <String>{...args.extensions, 'core'},
      handshake: session.handshake.plugins,
    );

    // ----- load the AGENTS.md operating guide (system prompt) ----------
    final ({String content, String hash}) agents =
        _loadAgentsMd(args.agentsMdPath, stderr);

    // ----- shared bring-up helper (replaces header build + host compose) -----
    final (:header, :host) = await bringUpSession(
      session: session,
      goal: goal,
      policy: args.policy,
      modelIdentifier: args.tier.name,
      buildIdentifier: 'cli',
      harnessVersion: _kHarnessVersion,
      coreTools: const <ToolDescriptor>[],
      extensionTools: extensionTools,
      agentsMd: agents.content,
      agentsMdHash: agents.hash,
      extraConfig: <String, dynamic>{
        'policy': args.policy.wireName,
        'requested_plugins': args.extensions,
      },
    );
    await writer.writeHeader(header);

    // ----- run loop -------------------------------------------------
    final SessionTermination termination = await session.run(
      host: host,
      provider: provider,
      writer: writer,
      turnBudget: args.turnBudget,
    );

    // ----- translate to exit code -----------------------------------
    if (termination.outcome == SessionOutcome.harnessError) {
      final String code = termination.harnessError?.wireName ?? 'unknown';
      stderr.writeln('harness_error: $code');
      return 1;
    }
    return 0;
  } on Object catch (e) {
    stderr.writeln('error: $e');
    return 1;
  } finally {
    await sub.cancel();
    await session.end();
  }
}

/// Render a [SessionProgressEvent] as a single human-readable line on
/// stdout. The sealed switch references every variant so the validation
/// grep (`SessionStarted|TurnBegan|ExtensionAutoDisabled|SessionEnded`)
/// has four hits in this file.
void _render(Stdout out, SessionProgressEvent e) {
  out.writeln(switch (e) {
    SessionStarted(:final goal) => '[session] started: $goal',
    TurnBegan(:final turn) => '[turn $turn] begin',
    ExtensionAutoDisabled(:final namespace, :final reason) =>
      '[plugin] auto-disabled $namespace ($reason)',
    SessionEnded() => '[session] ended',
  });
}

/// Load the AGENTS.md operating guide that gets pinned to the model's
/// system prompt (`'<agentsMd>\n\n## Goal\n<goal>'`).
///
/// Resolution order: an explicit [path] (`--agents-md`) wins; otherwise
/// the bundled template is resolved relative to the running script, then a
/// couple of cwd-relative fallbacks. Returns `('', '')` (empty prompt,
/// empty hash) when nothing is found — the harness then runs goal-only,
/// the historical behaviour. See lenny-cx6.53.
({String content, String hash}) _loadAgentsMd(String? path, IOSink stderr) {
  final List<String> candidates = <String>[];
  if (path != null && path.isNotEmpty) {
    candidates.add(path);
  } else {
    try {
      candidates.add(
        Platform.script.resolve('../templates/AGENTS.md').toFilePath(),
      );
    } on Object {
      // Non-file script URIs (e.g. data:) — skip script-relative resolve.
    }
    candidates.add('templates/AGENTS.md');
    candidates.add(kAgentsMdRelativePath);
  }
  for (final String c in candidates) {
    final File f = File(c);
    if (f.existsSync()) {
      final String content = f.readAsStringSync();
      stderr.writeln(
        'info: loaded AGENTS.md system prompt from $c '
        '(${content.length} chars).',
      );
      return (content: content, hash: _fnv1aHex(content));
    }
  }
  stderr.writeln(
    path != null && path.isNotEmpty
        ? 'warning: --agents-md "$path" not found; empty system prompt.'
        : 'warning: bundled AGENTS.md not found; empty system prompt.',
  );
  return (content: '', hash: '');
}

/// Dependency-free, stable 64-bit FNV-1a hash (hex) of [s]. Stamped into
/// the trajectory header `agents_md_hash` for provenance so the loaded
/// guide is identifiable across runs.
String _fnv1aHex(String s) {
  var hash = 0xcbf29ce484222325;
  const int prime = 0x100000001b3;
  for (final int cu in s.codeUnits) {
    hash = (hash ^ cu) * prime; // 64-bit two's-complement wrap on native
  }
  return (hash & 0x7fffffffffffffff).toRadixString(16);
}
