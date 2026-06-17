/// Public DTOs and progress events for [LeonardSession].
library;

/// Result of the `ext.exploration.core.handshake` exchange.
class HandshakeResult {
  const HandshakeResult({
    required this.contractVersion,
    required this.extensions,
    this.capabilities = const <String>[],
  });

  /// Contract version reported by the binding.
  final String contractVersion;

  /// Active extensions reported by the binding, with pre-namespaced tools.
  final List<ExtensionManifestEntry> extensions;

  /// Host-level capabilities that are reachable but are NOT namespaced
  /// [LeonardTool]s — so they never appear in [extensions]. The canonical
  /// one is `screenshot` (a raw `ext.exploration.core.screenshot` VM
  /// extension on the Flutter binding, debug/profile only). Surfaced here
  /// so a driver lists them where agents look: their absence from the tool
  /// manifest otherwise reads as "no such capability". Empty on hosts that
  /// expose none (e.g. the pure-Dart `ExplorationHost`).
  final List<String> capabilities;
}

/// One entry in the handshake extension manifest.
class ExtensionManifestEntry {
  const ExtensionManifestEntry({required this.namespace, required this.tools});

  /// Extension namespace (e.g. `router`).
  final String namespace;

  /// Bare tool tokens as reported by the binding's handshake (e.g.
  /// `go` for the `router` extension) — NOT namespaced. Callers that need
  /// the fully-qualified `<namespace>.<tool>` form join them with
  /// [namespace].
  final List<String> tools;
}

/// Per-session configuration consumed by later harness stories
/// (turn budgets, session budgets, max turns).
class LeonardConfig {
  const LeonardConfig({
    this.turnBudget = const Duration(seconds: 30),
    this.sessionBudget = const Duration(minutes: 15),
    this.maxTurns = 50,
  });

  final Duration turnBudget;
  final Duration sessionBudget;
  final int maxTurns;
}

/// Sealed base type for events emitted on
/// [LeonardSession.progress].
sealed class SessionProgressEvent {
  const SessionProgressEvent();
}

/// Emitted exactly once when [LeonardSession.start] succeeds.
class SessionStarted extends SessionProgressEvent {
  const SessionStarted(this.goal);
  final String goal;
}

/// Emitted at the start of each turn.
class TurnBegan extends SessionProgressEvent {
  const TurnBegan(this.turn);
  final int turn;
}

/// Emitted when [LeonardSession.disableExtension] auto-disables a extension.
class ExtensionAutoDisabled extends SessionProgressEvent {
  const ExtensionAutoDisabled(this.namespace, this.reason);
  final String namespace;
  final String reason;
}

/// Emitted exactly once when [LeonardSession.end] runs.
class SessionEnded extends SessionProgressEvent {
  const SessionEnded();
}
