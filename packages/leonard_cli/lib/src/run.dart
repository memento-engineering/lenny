/// Top-level CLI entrypoint composed by `bin/leonard_cli.dart`.
///
/// Parses argv, opens the trajectory file, builds a model provider,
/// connects an [LeonardSession], and drives the perception-action
/// loop via [LeonardSession.run] (which constructs a [LoopDriver]
/// on top of a caller-supplied [DefaultLoopHost]).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:leonard_acp/leonard_acp.dart' show AcpAgentSpec;
import 'package:leonard_agent/leonard_agent_io.dart';

import 'action_environment_loop_host.dart';
import 'cli_args.dart';
import 'file_trajectory_sink.dart';
import 'frame_capture_sink.dart';
import 'image_golden_comparator.dart';
import 'launcher.dart';
import 'provider_factory.dart';

/// Path the CLI advertises in `--help` for the bundled AGENTS.md.
const String kAgentsMdRelativePath = 'leonard_cli/templates/AGENTS.md';

/// Harness version stamped into the trajectory header. Bump when the
/// CLI emits a record-shape change consumers need to detect.
const String _kHarnessVersion = '0.6.0';

/// Run the CLI end-to-end. Returns the process exit code:
///   * 0  — clean session (any non-error termination)
///   * 64 — usage error (Unix convention)
///   * 1  — harness error or image-golden mismatch
///
/// [providerEnvironment] is the provider-construction environment seam. When
/// omitted, providers read the process environment. It also supplies the
/// `LEONARD_PRICE_INPUT_PER_MTOK` / `LEONARD_PRICE_OUTPUT_PER_MTOK` cost
/// override when the price flags are absent.
///
/// With `--summary-json`, the run's summary is written once the exit code is
/// known, on every path that got as far as opening the trajectory.
Future<int> runCli(
  List<String> argv, {
  required Stdin stdin,
  required Stdout stdout,
  required IOSink stderr,
  Map<String, String>? providerEnvironment,
  Future<ModelProvider> Function(AcpAgentSpec spec)? acpProviderBuilder,
}) async {
  final _RunSummary summary = _RunSummary();
  final int exitCode = await _runCli(
    argv,
    stdin: stdin,
    stdout: stdout,
    stderr: stderr,
    providerEnvironment: providerEnvironment,
    acpProviderBuilder: acpProviderBuilder,
    summary: summary,
  );
  await summary.write(exitCode, stderr: stderr);
  return exitCode;
}

Future<int> _runCli(
  List<String> argv, {
  required Stdin stdin,
  required Stdout stdout,
  required IOSink stderr,
  required _RunSummary summary,
  Map<String, String>? providerEnvironment,
  Future<ModelProvider> Function(AcpAgentSpec spec)? acpProviderBuilder,
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

  // ----- resolve goal (flag/file wins, stdin fallback) ---------------
  String? goal = args.goal;
  if (goal == null && args.goalFile != null) {
    try {
      goal = await File(args.goalFile!).readAsString();
    } on FileSystemException {
      stderr.writeln('error: --goal-file could not be read: ${args.goalFile}');
      return 64;
    }
    if (goal.trim().isEmpty) {
      stderr.writeln('error: --goal-file is empty: ${args.goalFile}');
      return 64;
    }
  }
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

  final Map<String, String> actionEnvironment;
  final ModelPricing pricing;
  try {
    actionEnvironment = _loadActionEnvironment(args.actionEnvironmentNames);
    pricing = _resolvePricing(
      args,
      providerEnvironment ?? Platform.environment,
    );
  } on CliUsageError catch (e) {
    stderr.writeln('error: ${e.message}');
    return 64;
  }

  // ----- open trajectory sink ---------------------------------------
  final String outPath =
      args.outputPath ?? FileTrajectorySink.defaultOutputPath();
  final String framesDirectory =
      args.framesDir ?? FileTrajectorySink.framesDirectoryFor(outPath);
  final FileTrajectorySink fileSink = await FileTrajectorySink.open(outPath);
  final FrameCaptureSink frameSink = FrameCaptureSink(
    delegate: fileSink,
    framesDirectory: framesDirectory,
    warningSink: stderr,
  );
  final TrajectoryWriter writer = TrajectoryWriter(frameSink);
  summary
    ..path = args.summaryJsonPath
    ..trajectoryPath = outPath
    ..modelIdentifier = args.modelIdentifier
    ..writer = writer;

  // ----- build provider (may throw on missing API key) --------------
  // Mint a per-run sessionId so the qwen-mlx tier can stamp every
  // request with X-Session-Id and an `leonard-<sessionId>-<ms>`
  // X-Conversation-Id (mirrors fs agent's `fsagent-<beadID>-<unixtime>`
  // convention). Slug ISO-8601 to keep the value safe for HTTP headers.
  final String sessionId = 'cli-${DateTime.now().toUtc().toIso8601String()}'
      .replaceAll(RegExp(r'[^A-Za-z0-9-]'), '-');
  final ModelProvider provider;
  try {
    provider = await buildProvider(
      args.tier,
      sessionId: sessionId,
      modelId: args.modelId,
      harness: args.harness,
      reasoningEffort: args.reasoningEffort,
      maxTokens: args.maxTokens,
      environment: providerEnvironment,
      acpProviderBuilder: acpProviderBuilder,
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
  } on StateError catch (error) {
    return _reportProviderConfigurationError(
      error,
      stderr: stderr,
      writer: writer,
    );
  } on AcpProviderConfigurationException catch (error) {
    return _reportProviderConfigurationError(
      error,
      stderr: stderr,
      writer: writer,
    );
  } on CliUsageError catch (error) {
    return _reportProviderConfigurationError(
      error,
      stderr: stderr,
      writer: writer,
    );
  }

  // ----- resolve the VM URI (boot the target first when --launch) ----
  // With --launch we own the target's lifecycle: boot it, drive the
  // discovered URI, and tear it down in the finally. Without --launch we
  // attach to a caller-provided --vm-uri and never touch its process.
  final Uri vmUri;
  LaunchHandle? launched;
  if (args.launch) {
    final TargetRunner runner = switch (args.runner) {
      LaunchRunner.flutter => TargetRunner.flutter,
      LaunchRunner.dart => TargetRunner.dart,
    };
    try {
      launched = await launchTarget(
        runner: runner,
        entrypoint: args.target!,
        device: args.device,
        onLog: stderr.writeln,
      );
    } on Object catch (e) {
      stderr.writeln('error: failed to launch target: $e');
      await writer.close(
        SessionFooter(
          outcome: SessionOutcome.harnessError,
          totalTurns: 0,
          totalDurationMs: 0,
          harnessError: 'connection_lost',
        ),
      );
      await disposeProvider(provider);
      return 1;
    }
    vmUri = launched.wsUri;
    stderr.writeln(
      'info: launched ${args.runner.name} target; VM service at $vmUri',
    );
  } else {
    vmUri = args.vmUri!;
  }

  // ----- connect session --------------------------------------------
  final LeonardSession session;
  try {
    session = await connectLeonardSession(vmUri);
  } on Object catch (e) {
    stderr.writeln('error: failed to connect to $vmUri: $e');
    await launched?.shutdown();
    await writer.close(
      SessionFooter(
        outcome: SessionOutcome.harnessError,
        totalTurns: 0,
        totalDurationMs: 0,
        harnessError: 'connection_lost',
      ),
    );
    await disposeProvider(provider);
    return 1;
  }

  // ----- progress renderer ------------------------------------------
  final StreamSubscription<SessionProgressEvent> sub = session.progress.listen(
    (e) => _render(stdout, e),
  );

  try {
    // ----- start session --------------------------------------------
    await session.start(
      goal,
      args.wallClockBudget == null
          ? LeonardConfig(
              coreBudgetBytes: args.coreBudgetBytes,
              pricing: pricing,
            )
          : LeonardConfig(
              coreBudgetBytes: args.coreBudgetBytes,
              sessionBudget: args.wallClockBudget!,
              pricing: pricing,
            ),
    );

    final String? probeArtifactPath = args.probeArtifactPath;
    if (probeArtifactPath != null) {
      final File artifact = File(probeArtifactPath);
      await artifact.parent.create(recursive: true);
      final Map<String, Object?> probe = await session.captureRawProbe(
        policy: args.policy,
      );
      await artifact.writeAsString('${jsonEncode(probe)}\n', flush: true);
    }

    // ----- extension warning block (unchanged) ----------------------------------
    final List<String> unknown = unknownExtensionNamespaces(
      requested: args.extensions,
      handshake: session.handshake.extensions,
    );
    for (final String ns in unknown) {
      stderr.writeln(
        'warning: --extensions includes "$ns" but the binding did not '
        'report an extension with that namespace; ignoring.',
      );
    }
    final List<ToolDescriptor> coreTools = <ToolDescriptor>[
      for (final ExtensionManifestEntry entry in session.handshake.extensions)
        if (entry.namespace == 'core') ...manifestToolDescriptors(entry),
    ];
    final Map<String, List<ToolDescriptor>> extensionTools =
        buildExtensionTools(
          requested: args.extensions,
          handshake: session.handshake.extensions,
        );

    // ----- load the AGENTS.md operating guide (system prompt) ----------
    final ({String content, String hash}) agents = _loadAgentsMd(
      args.agentsMdPath,
      stderr,
    );

    // ----- shared bring-up helper (replaces header build + host compose) -----
    final (:header, host: baseHost) = await bringUpSession(
      session: session,
      goal: goal,
      policy: args.policy,
      modelIdentifier: args.modelIdentifier,
      buildIdentifier: 'cli',
      harnessVersion: _kHarnessVersion,
      coreTools: coreTools,
      extensionTools: extensionTools,
      agentsMd: agents.content,
      agentsMdHash: agents.hash,
      extraConfig: <String, dynamic>{
        'policy': args.policy.wireName,
        'requested_extensions': args.extensions,
        'action_environment_names': args.actionEnvironmentNames,
        if (args.coreBudgetBytes != null)
          'core_budget_bytes': args.coreBudgetBytes,
      },
    );
    final LoopHost host = actionEnvironment.isEmpty
        ? baseHost
        : ActionEnvironmentLoopHost(
            delegate: baseHost,
            valuesByName: actionEnvironment,
          );
    await writer.writeHeader(header);

    // ----- run loop -------------------------------------------------
    final String? doneReasonPattern = args.doneReasonPattern;
    final String? doneEvidencePattern = args.doneEvidencePattern;
    final SessionTermination termination = await session.run(
      host: host,
      provider: provider,
      writer: writer,
      turnBudget: args.turnBudget,
      validator: ActionValidator(
        doneReasonPattern: doneReasonPattern == null
            ? null
            : RegExp(doneReasonPattern),
        doneEvidencePattern: doneEvidencePattern == null
            ? null
            : RegExp(doneEvidencePattern),
      ),
    );

    final String? goldensDirectory = args.goldensDir;
    final int goldenExitCode = goldensDirectory == null
        ? 0
        : await finishImageGoldenRun(
            framePaths: frameSink.capturedFramePaths,
            goldensDirectory: goldensDirectory,
            channelTolerance: args.goldenChannelTolerance,
            maxDiffRatio: args.goldenMaxDiffRatio,
            updateGoldens: args.updateGoldens,
            output: stdout,
            error: stderr,
          );

    // ----- translate to exit code -----------------------------------
    if (termination.outcome == SessionOutcome.harnessError) {
      final String code = termination.harnessError?.wireName ?? 'unknown';
      stderr.writeln('harness_error: $code');
      return 1;
    }
    return goldenExitCode;
  } on Object catch (e) {
    stderr.writeln('error: $e');
    return 1;
  } finally {
    try {
      await sub.cancel();
      await session.end();
      // Tear down a target we booted (no-op when attaching to --vm-uri).
      await launched?.shutdown();
    } finally {
      await disposeProvider(provider);
    }
  }
}

Future<int> _reportProviderConfigurationError(
  Object error, {
  required IOSink stderr,
  required TrajectoryWriter writer,
}) async {
  stderr.writeln('error: $error');
  await writer.close(
    const SessionFooter(
      outcome: SessionOutcome.harnessError,
      totalTurns: 0,
      totalDurationMs: 0,
      harnessError: 'config_error',
    ),
  );
  return 1;
}

/// The flag price pair outranks the `LEONARD_PRICE_*` env pair; with neither,
/// the built-in table applies.
ModelPricing _resolvePricing(CliArgs args, Map<String, String> env) {
  final double? flagInput = args.priceInputPerMTok;
  final double? flagOutput = args.priceOutputPerMTok;
  final (double?, double?) price = flagInput != null && flagOutput != null
      ? (flagInput, flagOutput)
      : parsePriceOverride(
          env['LEONARD_PRICE_INPUT_PER_MTOK'],
          env['LEONARD_PRICE_OUTPUT_PER_MTOK'],
          source:
              'LEONARD_PRICE_INPUT_PER_MTOK / LEONARD_PRICE_OUTPUT_PER_MTOK',
        );
  final (double? input, double? output) = price;
  if (input == null || output == null) return ModelPricing.defaults;
  return ModelPricing(
    override: ModelPrice(inputPerMTok: input, outputPerMTok: output),
  );
}

/// What `--summary-json` writes, filled in as the run gets far enough to
/// know each part.
class _RunSummary {
  String? path;
  String? trajectoryPath;
  String? modelIdentifier;
  TrajectoryWriter? writer;

  /// Writes the summary for a run that exited with [exitCode]. A no-op
  /// without `--summary-json`, or when the run stopped before opening its
  /// trajectory (argument and goal errors). A write failure is reported but
  /// never changes the exit code.
  Future<void> write(int exitCode, {required IOSink stderr}) async {
    final String? target = path;
    if (target == null) return;
    final SessionFooter? footer = writer?.footer;
    final Map<String, Object?> json = <String, Object?>{
      'schema': 'leonard.run_summary/1',
      'exit_code': exitCode,
      'outcome': footer?.toJson()['outcome'],
      if (footer?.harnessError != null) 'harness_error': footer!.harnessError,
      if (footer?.terminationDetail != null)
        'termination_detail': footer!.terminationDetail,
      'total_turns': footer?.totalTurns,
      'total_duration_ms': footer?.totalDurationMs,
      'model_identifier': modelIdentifier,
      'trajectory': trajectoryPath,
      'usage': footer?.usage,
    };
    try {
      final File file = File(target);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(json)}\n',
      );
    } on FileSystemException catch (e) {
      stderr.writeln('warning: --summary-json not written: ${e.message}');
    }
  }
}

Map<String, String> _loadActionEnvironment(List<String> names) {
  final Map<String, String> values = <String, String>{};
  for (final String name in names) {
    final String? value = Platform.environment[name];
    if (value == null || value.isEmpty) {
      throw CliUsageError('Missing required environment variable: $name');
    }
    values[name] = value;
  }
  return Map<String, String>.unmodifiable(values);
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
      '[extension] auto-disabled $namespace ($reason)',
    SessionEnded() => '[session] ended',
  });
}

/// Load the AGENTS.md operating guide that gets pinned to the model's
/// system prompt (`'<agentsMd>\n\n## Mission\n<goal>'`).
///
/// Resolution order: an explicit [path] (`--agents-md`) wins; otherwise
/// the bundled template is resolved relative to the running script, then a
/// couple of cwd-relative fallbacks. Returns `('', '')` (empty prompt,
/// empty hash) when nothing is found — the harness then runs goal-only,
/// the historical behaviour.
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
