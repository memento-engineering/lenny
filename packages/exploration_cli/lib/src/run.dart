/// Top-level CLI entrypoint composed by `bin/exploration_cli.dart`.
///
/// Parses argv, opens the trajectory file, builds a model provider,
/// connects an [ExplorationSession], and drives the perception-action
/// loop via [ExplorationSession.run] (which constructs a [LoopDriver]
/// on top of a caller-supplied [DefaultLoopHost]).
library;

import 'dart:async';
import 'dart:io';

import 'package:exploration_agent/exploration_agent.dart';

import 'cli_args.dart';
import 'file_trajectory_sink.dart';
import 'plugin_tools.dart';
import 'provider_factory.dart';

/// Path the CLI advertises in `--help` for the bundled AGENTS.md.
const String kAgentsMdRelativePath = 'exploration_cli/templates/AGENTS.md';

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
    stdout.writeln('Usage: exploration_cli [options]');
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
  // request with X-Session-Id and an `exploration-<sessionId>-<ms>`
  // X-Conversation-Id (mirrors fs agent's `fsagent-<beadID>-<unixtime>`
  // convention). Slug ISO-8601 to keep the value safe for HTTP headers.
  final String sessionId =
      'cli-${DateTime.now().toUtc().toIso8601String()}'
          .replaceAll(RegExp(r'[^A-Za-z0-9-]'), '-');
  final ModelProvider provider;
  try {
    provider = buildProvider(args.tier, sessionId: sessionId);
  } on StateError catch (e) {
    stderr.writeln('error: ${e.message}');
    await writer.close(SessionFooter(
      outcome: SessionOutcome.harnessError,
      finalSummary: '',
      totalTurns: 0,
      totalDurationMs: 0,
      harnessError: 'config_error',
    ));
    return 1;
  }

  // ----- connect session --------------------------------------------
  final ExplorationSession session;
  try {
    session = await ExplorationSession.connect(args.vmUri);
  } on Object catch (e) {
    stderr.writeln('error: failed to connect to ${args.vmUri}: $e');
    await writer.close(SessionFooter(
      outcome: SessionOutcome.harnessError,
      finalSummary: '',
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
    await session.start(goal, const ExplorationConfig());

    // ----- plugin warning block (unchanged) ----------------------------------
    final List<String> unknown = unknownPluginNamespaces(
      requested: args.plugins,
      handshake: session.handshake.plugins,
    );
    for (final String ns in unknown) {
      stderr.writeln(
        'warning: --plugins includes "$ns" but the binding did not '
        'report a plugin with that namespace; ignoring.',
      );
    }
    final Map<String, List<ToolDescriptor>> pluginTools = buildPluginTools(
      requested: args.plugins,
      handshake: session.handshake.plugins,
    );

    // ----- shared bring-up helper (replaces header build + host compose) -----
    final (:header, :host) = await bringUpSession(
      session: session,
      goal: goal,
      policy: args.policy,
      modelIdentifier: args.tier.name,
      buildIdentifier: 'cli',
      harnessVersion: _kHarnessVersion,
      coreTools: const <ToolDescriptor>[],
      pluginTools: pluginTools,
      agentsMd: '',
      extraConfig: <String, dynamic>{
        'policy': args.policy.wireName,
        'requested_plugins': args.plugins,
      },
    );
    await writer.writeHeader(header);

    // ----- run loop -------------------------------------------------
    final SessionTermination termination = await session.run(
      host: host,
      provider: provider,
      writer: writer,
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
/// grep (`SessionStarted|TurnBegan|PluginAutoDisabled|SessionEnded`)
/// has four hits in this file.
void _render(Stdout out, SessionProgressEvent e) {
  out.writeln(switch (e) {
    SessionStarted(:final goal) => '[session] started: $goal',
    TurnBegan(:final turn) => '[turn $turn] begin',
    PluginAutoDisabled(:final namespace, :final reason) =>
      '[plugin] auto-disabled $namespace ($reason)',
    SessionEnded() => '[session] ended',
  });
}
