/// Per-turn event stream type consumed by the DevTools Thinking and
/// Timeline panels (PRD §6.3).
///
/// Web-compatible: pure Dart, no `dart:io`.
library;

import '../provider/types.dart' show ThinkingDelta;

/// One event in the per-turn stream.
///
/// Subtypes:
/// * [TurnThinking] — a single reasoning delta from the provider.
/// * [TurnActionDecided] — the action chosen for this turn (post-validation).
/// * [TurnValidation] — validation outcome for the chosen action.
/// * [TurnComplete] — turn boundary marker (end-of-turn).
sealed class TurnEvent {
  const TurnEvent(this.turn);

  /// Zero-based turn index this event belongs to.
  final int turn;
}

/// One reasoning delta from the model provider's `thinking()` stream.
class TurnThinking extends TurnEvent {
  const TurnThinking(super.turn, this.delta);

  /// The provider-emitted reasoning fragment.
  final ThinkingDelta delta;
}

/// The action the loop chose for this turn (post-validation).
class TurnActionDecided extends TurnEvent {
  const TurnActionDecided(super.turn, this.toolName, this.args);

  /// Pre-namespaced tool name (e.g. `core.tap`).
  final String toolName;

  /// Validated argument map for the tool.
  final Map<String, dynamic> args;
}

/// Validation outcome for the turn's chosen action.
class TurnValidation extends TurnEvent {
  const TurnValidation(super.turn, this.ok, this.rejectReason);

  /// Whether the validator accepted the action.
  final bool ok;

  /// Rejection reason when [ok] is false; null otherwise.
  final String? rejectReason;
}

/// End-of-turn marker.
class TurnComplete extends TurnEvent {
  const TurnComplete(super.turn);
}
