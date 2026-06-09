/// Loop-driver-local value types and exceptions.
///
/// Distinct from the session-level outcome enum
/// (`SessionOutcome` from `trajectory/records.dart`); the driver
/// re-uses that enum for the trajectory footer and exposes
/// [SessionTermination] as the structured return value of
/// [LoopDriver.runSession]. PRD §10, §17.
library;

import 'package:meta/meta.dart';

import '../trajectory/records.dart' show SessionOutcome;

/// Sub-classification of a session that ended with
/// [SessionOutcome.harnessError]. Mirrors the wire-level
/// `harness_error` field carried in the trajectory footer.
enum HarnessError {
  /// Three consecutive failed turns — model could not produce a valid
  /// action against the current observation. PRD §17.
  agentStuck,

  /// VM-service transport error mid-session (e.g. socket dropped while
  /// the binding was still being driven).
  connectionLost,
}

/// Wire name for [HarnessError] values, as written to the trajectory
/// footer's `harness_error` string.
extension HarnessErrorWire on HarnessError {
  String get wireName => switch (this) {
        HarnessError.agentStuck => 'agent_stuck',
        HarnessError.connectionLost => 'connection_lost',
      };
}

/// Structured return value from [LoopDriver.runSession].
@immutable
class SessionTermination {
  const SessionTermination(
    this.outcome, {
    this.harnessError,
    this.finalSummary,
    this.terminationDetail,
  });

  /// Top-level outcome enum (mirrors trajectory footer).
  final SessionOutcome outcome;

  /// Sub-classification when [outcome] is [SessionOutcome.harnessError].
  final HarnessError? harnessError;

  /// For [SessionOutcome.done], the model-supplied `reason` argument
  /// from the `core.done` action.
  final String? finalSummary;

  /// Optional sub-reason for the termination. Carried through to the
  /// trajectory footer as `termination_detail`. Example:
  /// `'inference_latency'` when consecutive turn-timeouts exhausted the
  /// separate timeout tolerance.
  final String? terminationDetail;

  @override
  bool operator ==(Object other) =>
      other is SessionTermination &&
      outcome == other.outcome &&
      harnessError == other.harnessError &&
      finalSummary == other.finalSummary &&
      terminationDetail == other.terminationDetail;

  @override
  int get hashCode =>
      Object.hash(outcome, harnessError, finalSummary, terminationDetail);

  @override
  String toString() =>
      'SessionTermination($outcome, harnessError: $harnessError, '
      'finalSummary: $finalSummary, terminationDetail: $terminationDetail)';
}

/// Thrown by the per-turn budget when a single turn exceeds the wall-
/// clock budget (PRD §10, default 30s).
@immutable
class TurnTimeoutError implements Exception {
  const TurnTimeoutError(this.turnIndex);
  final int turnIndex;

  @override
  String toString() => 'TurnTimeoutError(turn=$turnIndex)';
}

/// Thrown by [LoopDriver.runTurn] when a turn fails for a reason that
/// counts toward a failure budget (PRD §17).
///
/// `reason` is one of:
///   * `'invalid_action_exhausted'` — validator rejected three times;
///     counts toward consecutive-failed-turns.
///   * `'schema_exhausted'` — provider raised [SchemaRejection] twice;
///     counts toward consecutive-failed-turns.
///   * `'turn_timeout'` — per-turn 120s budget expired; counts toward
///     the separate consecutive-turn-timeouts counter.
@immutable
class TurnFailure implements Exception {
  const TurnFailure(this.turnIndex, this.reason, [this.cause]);

  final int turnIndex;
  final String reason;
  final Object? cause;

  @override
  String toString() => 'TurnFailure(turn=$turnIndex, reason=$reason)';
}

/// Raised by [LoopDriver.runSession] when the underlying VM-service
/// transport emits an unrecoverable error mid-session (e.g. the
/// websocket dropped). The driver translates this into a
/// [HarnessError.connectionLost] termination.
///
/// Distinct from [BindingNotInitializedError] (.11), which is raised
/// during handshake — before any turns run — and propagates unwrapped.
class VmServiceConnectionLost implements Exception {
  const VmServiceConnectionLost([this.cause]);
  final Object? cause;

  @override
  String toString() =>
      'VmServiceConnectionLost${cause == null ? '' : ': $cause'}';
}
