/// Public DTOs and progress events for [ExplorationSession].
library;

/// Result of the `ext.exploration.core.handshake` exchange.
class HandshakeResult {
  const HandshakeResult({
    required this.contractVersion,
    required this.plugins,
  });

  /// Contract version reported by the binding.
  final String contractVersion;

  /// Active plugins reported by the binding, with pre-namespaced tools.
  final List<PluginManifestEntry> plugins;
}

/// One entry in the handshake plugin manifest.
class PluginManifestEntry {
  const PluginManifestEntry({
    required this.namespace,
    required this.tools,
  });

  /// Plugin namespace (e.g. `router`).
  final String namespace;

  /// Bare tool tokens as reported by the binding's handshake (e.g.
  /// `go` for the `router` plugin) — NOT namespaced. Callers that need
  /// the fully-qualified `<namespace>.<tool>` form join them with
  /// [namespace].
  final List<String> tools;
}

/// Per-session configuration consumed by later harness stories
/// (turn budgets, session budgets, max turns).
class ExplorationConfig {
  const ExplorationConfig({
    this.turnBudget = const Duration(seconds: 30),
    this.sessionBudget = const Duration(minutes: 15),
    this.maxTurns = 50,
  });

  final Duration turnBudget;
  final Duration sessionBudget;
  final int maxTurns;
}

/// Sealed base type for events emitted on
/// [ExplorationSession.progress].
sealed class SessionProgressEvent {
  const SessionProgressEvent();
}

/// Emitted exactly once when [ExplorationSession.start] succeeds.
class SessionStarted extends SessionProgressEvent {
  const SessionStarted(this.goal);
  final String goal;
}

/// Emitted at the start of each turn (consumed by .12 / .23).
class TurnBegan extends SessionProgressEvent {
  const TurnBegan(this.turn);
  final int turn;
}

/// Emitted when [ExplorationSession.disablePlugin] auto-disables a plugin.
class PluginAutoDisabled extends SessionProgressEvent {
  const PluginAutoDisabled(this.namespace, this.reason);
  final String namespace;
  final String reason;
}

/// Emitted exactly once when [ExplorationSession.end] runs.
class SessionEnded extends SessionProgressEvent {
  const SessionEnded();
}
