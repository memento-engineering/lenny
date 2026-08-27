/// Launch description for an ACP-compatible agent process.
///
/// This is the whole of leonard_acp's agent-specific knowledge: a command,
/// its arguments, and its environment. `codex`, `copilot`, `opencode` and
/// `gemini` are VALUES of this type, never branches in the provider. Keep it
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

  /// OpenAI Codex via the ACP adapter.
  ///
  /// `codex` serves no ACP itself; the adapter starts the Codex App Server and
  /// translates ACP requests into Codex operations. Authentication rides the
  /// operator's existing Codex config (ChatGPT auth), which is why this is the
  /// default: no separate credential and no borrowed org credits.
  ///
  /// There is deliberately NO `claudeAgent` factory. Anthropic is reachable in
  /// one hop through `AnthropicBackend`, so routing Claude through
  /// ACP -> Claude Agent SDK -> Anthropic API would be a longer path to the
  /// same model with nothing gained.
  ///
  /// NOTE on model selection: power_station's builtin `codex` environment pins
  /// `gpt-5.6-sol` because claude's tier names 400 on codex under ChatGPT auth
  /// (bead `pow-a9o`). ACP exposes `session/set_model`; if this graduates past
  /// the spike, honour that pin rather than assuming a default.
  factory AcpAgentSpec.codex({
    String package = '@agentclientprotocol/codex-acp',
    Map<String, String> env = const <String, String>{},
  }) => AcpAgentSpec(
    label: 'codex-acp',
    command: 'npx',
    args: <String>['-y', package],
    env: env,
  );

  /// GitHub Copilot CLI's built-in ACP server (public preview).
  ///
  /// Unlike [AcpAgentSpec.codex] this needs no adapter — `copilot` serves ACP
  /// itself. Named in the org's D-4 ruling as one of the two agents the first
  /// ACP adapter must prove (`the_grid/docs/SCRATCH-third-party-harnesses.md`).
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
