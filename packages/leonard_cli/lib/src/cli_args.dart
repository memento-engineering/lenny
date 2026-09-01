/// Argument parser for `leonard_cli`. Pure value types — no
/// `dart:io`. The thin wrapper [parseCliArgs] turns argv into a typed
/// [CliArgs] or throws [CliUsageError]; [buildParser] is exposed so the
/// `--help` path can render usage text.
library;

import 'package:args/args.dart';
import 'package:leonard_agent/leonard_agent.dart' show StabilityPolicy;

/// Model tier selected via `--model`. Each tier has a fixed default
/// configuration applied by `provider_factory.dart` (PRD §16.4).
enum ModelTier { qwenMlx, claude, openai }

/// How `--launch` boots the target. Pure mirror of `launcher.dart`'s
/// `TargetRunner` (kept here so `cli_args` stays `dart:io`-free); mapped to
/// it at the io boundary in `run.dart`.
enum LaunchRunner { flutter, dart }

/// Parsed CLI arguments. The `goal` may still be `null` here when
/// `--goal` was omitted; the caller (`runCli`) reads [goalFile] or stdin.
class CliArgs {
  const CliArgs({
    required this.goal,
    required this.vmUri,
    required this.tier,
    required this.outputPath,
    required this.policy,
    required this.extensions,
    this.goalFile,
    this.actionEnvironmentNames = const <String>[],
    this.launch = false,
    this.runner = LaunchRunner.flutter,
    this.device,
    this.target,
    this.agentsMdPath,
    this.turnBudget,
    this.coreBudgetBytes,
    this.probeArtifactPath,
    this.doneReasonPattern,
  });

  /// Goal to drive the app toward, supplied via `--goal`. `null` means use
  /// [goalFile], or read from stdin when that is also absent.
  final String? goal;

  /// UTF-8 goal file loaded by `runCli`; mutually exclusive with [goal].
  final String? goalFile;

  /// Flutter VM service ws:// URI. `null` when `--launch` is set (the URI is
  /// discovered at runtime by booting the target); non-null otherwise.
  /// Exactly one of [vmUri] / [launch] is provided.
  final Uri? vmUri;

  /// When true, boot the target ([runner] / [device] / [target]) and drive
  /// the discovered URI. Mutually exclusive with [vmUri].
  final bool launch;

  /// `--launch`: how to boot the target.
  final LaunchRunner runner;

  /// `--launch`: Flutter device id (`-d`); only meaningful with
  /// [LaunchRunner.flutter]. `null` lets the runner pick.
  final String? device;

  /// `--launch`: entrypoint Dart file (`-t`) to run. Required when [launch].
  final String? target;

  /// Selected model tier (`--model`).
  final ModelTier tier;

  /// Optional `--output` override. When `null` the CLI writes to
  /// `./trajectories/<UTC-timestamp>.jsonl`.
  final String? outputPath;

  /// Stability policy (`--policy`) — already mapped to the agent's
  /// [StabilityPolicy] enum.
  final StabilityPolicy policy;

  /// Extension namespaces requested via `--extensions`. Empty when not
  /// supplied.
  final List<String> extensions;

  /// Environment names whose exact `${NAME}` action arguments are resolved
  /// immediately before target dispatch.
  final List<String> actionEnvironmentNames;

  /// Optional `--agents-md` path override for the system-prompt operating
  /// guide. When `null` the CLI loads the bundled template (resolved
  /// relative to the running script); a missing bundled template falls
  /// back to an empty system prompt.
  final String? agentsMdPath;

  /// Optional `--turn-budget` override. `null` means use the LoopDriver
  /// default (120 s).
  final Duration? turnBudget;

  /// Positive core-observation byte budget forwarded on every pull.
  /// `null` uses the binding default.
  final int? coreBudgetBytes;

  /// Path to write raw handshake and observation JSON after session start.
  final String? probeArtifactPath;

  /// Scenario-declared regular expression a `core.done` `reason` must match.
  /// `null` leaves `core.done` reasons unconstrained.
  final String? doneReasonPattern;
}

/// Thrown by [parseCliArgs] for any user-facing argument error. The
/// caller renders the message + parser usage to stderr and exits 64.
class CliUsageError implements Exception {
  CliUsageError(this.message);
  final String message;

  @override
  String toString() => 'CliUsageError: $message';
}

/// Build the canonical [ArgParser]. Exposed for `--help` rendering and
/// reuse from tests.
ArgParser buildParser() => ArgParser()
  ..addOption('goal', help: 'Goal to drive the app toward (or pipe via stdin).')
  ..addOption(
    'goal-file',
    help: 'Read the goal from a UTF-8 file; mutually exclusive with --goal.',
  )
  ..addOption(
    'vm-uri',
    help: 'Flutter VM service ws:// URI (required unless --launch).',
  )
  ..addFlag(
    'launch',
    negatable: false,
    help:
        'Boot the target first (see --runner/-d/-t), discover its VM '
        'service URI, then drive it. Mutually exclusive with --vm-uri.',
  )
  ..addOption(
    'runner',
    defaultsTo: 'flutter',
    allowed: <String>['flutter', 'dart'],
    help: '--launch: how to boot the target (flutter run | dart run).',
  )
  ..addOption(
    'device',
    abbr: 'd',
    help: '--launch: Flutter device id (flutter runner only).',
  )
  ..addOption(
    'target',
    abbr: 't',
    help: '--launch: entrypoint Dart file to run.',
  )
  ..addOption(
    'model',
    defaultsTo: 'claude',
    allowed: <String>['qwen-mlx', 'claude', 'openai'],
    help: 'Model tier (PRD 16.4).',
  )
  ..addOption(
    'output',
    help: 'Trajectory path (default ./trajectories/<UTC-timestamp>.jsonl).',
  )
  ..addOption(
    'policy',
    defaultsTo: 'action-relative',
    allowed: <String>['idle', 'frame-stable', 'action-relative'],
    help: 'Stability policy.',
  )
  ..addOption(
    'extensions',
    defaultsTo: '',
    help: 'Comma-separated extension namespaces (e.g. router,riverpod,dio).',
  )
  ..addMultiOption(
    'action-env',
    help:
        'Resolve exact \${NAME} action arguments from NAME at dispatch; '
        'the model and trajectory retain the placeholder.',
  )
  ..addOption(
    'agents-md',
    help:
        'Path to an AGENTS.md operating guide pinned to the system '
        'prompt. Defaults to the bundled template; missing => empty.',
  )
  ..addOption(
    'turn-budget',
    help: 'Per-turn inference timeout in seconds (default: 120).',
  )
  ..addOption(
    'core-budget-bytes',
    help: 'Positive core-observation byte budget sent on every pull.',
  )
  ..addOption(
    'probe-artifact',
    help: 'Write raw handshake and observation JSON after session start.',
  )
  ..addOption(
    'done-reason-pattern',
    help:
        'Regular expression a core.done reason must match; a mismatch is '
        'fed back to the model as a validation error and the turn retries.',
  )
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Print this help.');

/// Parse argv into [CliArgs]. Throws [CliUsageError] on any malformed
/// or missing-required argument; the caller is responsible for the
/// stderr message + exit-code-64 contract.
CliArgs parseCliArgs(List<String> argv) {
  final ArgParser parser = buildParser();
  final ArgResults res;
  try {
    res = parser.parse(argv);
  } on ArgParserException catch (e) {
    throw CliUsageError(e.message);
  } on FormatException catch (e) {
    throw CliUsageError(e.message);
  }

  final String? goalFile = res['goal-file'] as String?;
  if (goalFile != null && goalFile.isNotEmpty && res['goal'] != null) {
    throw CliUsageError('--goal and --goal-file are mutually exclusive');
  }

  final List<String> actionEnvironmentNames =
      (res['action-env'] as List<String>).toSet().toList(growable: false);
  final RegExp environmentName = RegExp(r'^[A-Z][A-Z0-9_]*$');
  for (final String name in actionEnvironmentNames) {
    if (!environmentName.hasMatch(name)) {
      throw CliUsageError(
        '--action-env must be an uppercase environment name; got "$name"',
      );
    }
  }

  // Exactly one source of the VM URI: an explicit --vm-uri, or --launch
  // (which boots a target and discovers it). "No dual mode" — supplying
  // both, or neither, is a hard usage error rather than a silent pick.
  final bool launch = res['launch'] as bool;
  final Object? rawVmUri = res['vm-uri'];
  if (launch && rawVmUri != null) {
    throw CliUsageError('--launch and --vm-uri are mutually exclusive');
  }
  Uri? vmUri;
  if (!launch) {
    if (rawVmUri == null) {
      throw CliUsageError(
        'Missing required flag: --vm-uri (or use --launch to boot a target)',
      );
    }
    vmUri = Uri.tryParse(rawVmUri as String);
    if (vmUri == null || (!vmUri.isScheme('ws') && !vmUri.isScheme('wss'))) {
      throw CliUsageError('Invalid --vm-uri: must be a ws:// or wss:// URI');
    }
  }

  final LaunchRunner runner = switch (res['runner'] as String) {
    'flutter' => LaunchRunner.flutter,
    'dart' => LaunchRunner.dart,
    _ => throw CliUsageError('Invalid --runner'),
  };
  final String? device = res['device'] as String?;
  final String? target = res['target'] as String?;
  if (launch) {
    if (target == null || target.isEmpty) {
      throw CliUsageError('--launch requires --target <entrypoint.dart>');
    }
    if (runner == LaunchRunner.dart && device != null && device.isNotEmpty) {
      throw CliUsageError(
        '--device is meaningless with --runner dart; drop -d',
      );
    }
  } else {
    // Boot-only flags without --launch are a mistake, not a no-op.
    if (device != null && device.isNotEmpty) {
      throw CliUsageError('--device only applies with --launch');
    }
    if (target != null && target.isNotEmpty) {
      throw CliUsageError('--target only applies with --launch');
    }
  }

  final ModelTier tier = switch (res['model'] as String) {
    'qwen-mlx' => ModelTier.qwenMlx,
    'claude' => ModelTier.claude,
    'openai' => ModelTier.openai,
    _ => throw CliUsageError('Invalid --model'),
  };

  final StabilityPolicy policy = switch (res['policy'] as String) {
    'idle' => StabilityPolicy.quietFrame,
    'frame-stable' => StabilityPolicy.boundedStability,
    'action-relative' => StabilityPolicy.actionRelative,
    _ => throw CliUsageError('Invalid --policy'),
  };

  final String extensionsRaw = (res['extensions'] as String).trim();
  final List<String> extensions = extensionsRaw.isEmpty
      ? const <String>[]
      : extensionsRaw
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(growable: false);

  final String? rawTurnBudget = res['turn-budget'] as String?;
  Duration? turnBudget;
  if (rawTurnBudget != null) {
    final int? secs = int.tryParse(rawTurnBudget);
    if (secs == null || secs <= 0) {
      throw CliUsageError(
        '--turn-budget must be a positive integer (seconds); got "$rawTurnBudget"',
      );
    }
    turnBudget = Duration(seconds: secs);
  }

  final String? rawCoreBudgetBytes = res['core-budget-bytes'] as String?;
  int? coreBudgetBytes;
  if (rawCoreBudgetBytes != null) {
    coreBudgetBytes = int.tryParse(rawCoreBudgetBytes);
    if (coreBudgetBytes == null || coreBudgetBytes <= 0) {
      throw CliUsageError(
        '--core-budget-bytes must be a positive integer; '
        'got "$rawCoreBudgetBytes"',
      );
    }
  }

  final String? doneReasonPattern = res['done-reason-pattern'] as String?;
  if (doneReasonPattern != null) {
    if (doneReasonPattern.isEmpty) {
      throw CliUsageError('--done-reason-pattern must not be empty');
    }
    try {
      RegExp(doneReasonPattern);
    } on FormatException catch (e) {
      throw CliUsageError(
        '--done-reason-pattern is not a valid regular expression: '
        '${e.message}',
      );
    }
  }

  return CliArgs(
    goal: res['goal'] as String?,
    goalFile: goalFile,
    vmUri: vmUri,
    tier: tier,
    outputPath: res['output'] as String?,
    policy: policy,
    extensions: extensions,
    actionEnvironmentNames: actionEnvironmentNames,
    launch: launch,
    runner: runner,
    device: device,
    target: target,
    agentsMdPath: res['agents-md'] as String?,
    turnBudget: turnBudget,
    coreBudgetBytes: coreBudgetBytes,
    probeArtifactPath: res['probe-artifact'] as String?,
    doneReasonPattern: doneReasonPattern,
  );
}
