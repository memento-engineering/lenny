/// Launch description for an ACP-compatible agent process.
///
/// This is the whole of leonard_acp's agent-specific knowledge: a command,
/// its arguments, and its environment. `claude`, `copilot`, `gemini` and
/// `codex` are VALUES of this type, never branches in the provider. Keep it
/// that way — the point of riding ACP is that adding an agent is a config
/// line, not a code path.
library;

import 'package:meta/meta.dart';

/// How to spawn one ACP agent over stdio.
@immutable
class AcpAgentSpec {
  const AcpAgentSpec({
    required this.label,
    required this.command,
    required this.args,
    this.env = const <String, String>{},
  });

  /// Claude Code via the official ACP adapter.
  ///
  /// `claude` itself has NO `--acp` flag (verified against 2.1.246); ACP is
  /// served by an adapter package that wraps the Claude Agent SDK.
  /// Authentication rides the SDK — existing Claude Code credentials or
  /// `ANTHROPIC_API_KEY` — so this costs Claude usage, not Copilot credits.
  ///
  /// The adapter was renamed from `@zed-industries/claude-code-acp`, which is
  /// deprecated at 0.16.2. Do not take the old name from older docs.
  factory AcpAgentSpec.claudeAgent({
    String package = '@agentclientprotocol/claude-agent-acp',
    Map<String, String> env = const <String, String>{},
  }) => AcpAgentSpec(
    label: 'claude-agent-acp',
    command: 'npx',
    args: <String>['-y', package],
    env: env,
  );

  /// GitHub Copilot CLI's built-in ACP server (public preview).
  ///
  /// Unlike [AcpAgentSpec.claudeAgent] this needs no adapter — `copilot`
  /// serves ACP itself.
  factory AcpAgentSpec.copilot({
    Map<String, String> env = const <String, String>{},
  }) => AcpAgentSpec(
    label: 'copilot',
    command: 'copilot',
    args: const <String>['--acp'],
    env: env,
  );

  /// Human-readable name for logs and trajectory metadata.
  final String label;

  /// Executable to spawn.
  final String command;

  /// Arguments passed to [command].
  final List<String> args;

  /// Extra environment entries merged over the inherited environment.
  final Map<String, String> env;

  @override
  String toString() => 'AcpAgentSpec($label: $command ${args.join(' ')})';
}
