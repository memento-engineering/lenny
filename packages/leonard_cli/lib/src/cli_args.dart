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

/// Parsed CLI arguments. The `goal` may still be `null` here when
/// `--goal` was omitted; the caller (`runCli`) reads stdin as a
/// fallback when stdin is not a TTY.
class CliArgs {
  const CliArgs({
    required this.goal,
    required this.vmUri,
    required this.tier,
    required this.outputPath,
    required this.policy,
    required this.extensions,
    this.agentsMdPath,
    this.turnBudget,
  });

  /// Exploration goal supplied via `--goal`. `null` means "read from
  /// stdin if stdin is not a TTY".
  final String? goal;

  /// Flutter VM service ws:// URI (required).
  final Uri vmUri;

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

  /// Optional `--agents-md` path override for the system-prompt operating
  /// guide. When `null` the CLI loads the bundled template (resolved
  /// relative to the running script); a missing bundled template falls
  /// back to an empty system prompt.
  final String? agentsMdPath;

  /// Optional `--turn-budget` override. `null` means use the LoopDriver
  /// default (120 s).
  final Duration? turnBudget;
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
  ..addOption(
    'goal',
    help: 'Exploration goal (or pipe via stdin).',
  )
  ..addOption(
    'vm-uri',
    mandatory: true,
    help: 'Flutter VM service ws:// URI (required).',
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
  ..addOption(
    'agents-md',
    help: 'Path to an AGENTS.md operating guide pinned to the system '
        'prompt. Defaults to the bundled template; missing => empty.',
  )
  ..addOption(
    'turn-budget',
    help: 'Per-turn inference timeout in seconds (default: 120).',
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

  // `mandatory: true` causes res['vm-uri'] to throw ArgumentError when
  // the flag was not supplied; intercept that and surface as a usage
  // error.
  final Object? rawVmUri;
  try {
    rawVmUri = res['vm-uri'];
  } on ArgumentError {
    throw CliUsageError('Missing required flag: --vm-uri');
  }
  if (rawVmUri == null) {
    throw CliUsageError('Missing required flag: --vm-uri');
  }
  final Uri? vmUri = Uri.tryParse(rawVmUri as String);
  if (vmUri == null || (!vmUri.isScheme('ws') && !vmUri.isScheme('wss'))) {
    throw CliUsageError(
      'Invalid --vm-uri: must be a ws:// or wss:// URI',
    );
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

  return CliArgs(
    goal: res['goal'] as String?,
    vmUri: vmUri,
    tier: tier,
    outputPath: res['output'] as String?,
    policy: policy,
    extensions: extensions,
    agentsMdPath: res['agents-md'] as String?,
    turnBudget: turnBudget,
  );
}
