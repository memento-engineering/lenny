/// Value types for the dogfood harness. Library-internal: not exported
/// from `lib/exploration_agent.dart` per the harness's "private until
/// the pattern proves itself" policy (bead lenny-cx6.43).
library;

import 'package:meta/meta.dart';

/// Terminal outcome of one `AgentDogfoodHarness.run()` call.
///
/// Maps 1:1 to the CLI's exit-code table:
///   completedWithToolCall  -> 0
///   completedNoToolCall    -> 0
///   typedException         -> 1
///   budgetExceeded         -> 2
/// (Configuration errors exit 3 from the CLI shim; they are caught
///  before the harness runs and never produce a [DogfoodRunResult].)
enum DogfoodOutcome {
  /// The session loop completed and at least one validated tool call
  /// was dispatched into the binding fake.
  completedWithToolCall,

  /// The session loop completed without ever dispatching a tool call
  /// (e.g. budget exhausted, the model produced only text, or the
  /// driver terminated for a non-error reason).
  completedNoToolCall,

  /// A typed agent exception surfaced (e.g. [SchemaRejection],
  /// `ArgumentError`, `BindingNotInitializedError`).
  typedException,

  /// The per-turn or total wall-clock budget elapsed before the run
  /// completed.
  budgetExceeded,
}

/// Structured result of one harness invocation.
@immutable
class DogfoodRunResult {
  const DogfoodRunResult({
    required this.outcome,
    required this.tracePath,
    required this.turnCount,
    required this.toolCallCount,
    this.exception,
  });

  /// Terminal classification of the run.
  final DogfoodOutcome outcome;

  /// Path to the JSONL trace written by the harness. The string
  /// `'<memory>'` (or any other caller-supplied marker) is preserved
  /// verbatim when the caller passes an in-memory sink.
  final String tracePath;

  /// Maximum-turn budget the harness was configured for. The
  /// underlying loop driver may have terminated earlier; this field
  /// records the configured cap rather than the executed count.
  final int turnCount;

  /// Number of validated tool calls dispatched into the binding fake
  /// during the run.
  final int toolCallCount;

  /// The thrown exception when [outcome] is [DogfoodOutcome.typedException]
  /// or [DogfoodOutcome.budgetExceeded]; `null` otherwise.
  final Object? exception;
}

/// Thrown synchronously from [AgentDogfoodHarness.run()] (and from the
/// fixture loader) when the caller supplied invalid configuration — an
/// unreadable fixture file, a non-positive budget, etc. The CLI shim
/// catches this and exits 3.
class DogfoodConfigError extends ArgumentError {
  DogfoodConfigError(String super.message);
}
