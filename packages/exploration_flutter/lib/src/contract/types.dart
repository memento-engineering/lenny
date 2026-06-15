/// Value types for the v1 plugin contract (PRD §7).
///
/// EXPERIMENTAL — v1 plugin contract. See [ExplorationPlugin] for the
/// full versioning posture.
library;

/// Opaque holder for a JSON Schema fragment describing a tool's input.
class JsonSchema {
  const JsonSchema(this.raw);

  /// The raw JSON Schema fragment.
  final Map<String, Object?> raw;
}

/// Outcome of an [ExplorationTool] invocation.
class ToolResult {
  const ToolResult({required this.ok, this.value, this.error});

  /// Whether the tool ran to completion without error.
  final bool ok;

  /// Optional payload returned by the tool when [ok] is `true`.
  final Object? value;

  /// Optional error message when [ok] is `false`.
  final String? error;
}

/// Whether a plugin reports the app as busy (settling, loading, animating, ...).
class BusyState {
  const BusyState({
    required this.isBusy,
    this.reason,
    this.estimatedDuration,
  });

  /// `true` when the plugin reports an in-flight activity.
  final bool isBusy;

  /// Optional human-readable reason (e.g. "navigating", "loading users").
  final String? reason;

  /// Optional estimate for when busy is expected to clear.
  final Duration? estimatedDuration;

  /// Idle sentinel returned by exception-isolated dispatch and by plugins
  /// that have no contribution.
  static const BusyState idle = BusyState(isBusy: false);
}

/// Record of a tool the harness just executed; passed to
/// [ExplorationPlugin.onActionExecuted].
class ExecutedAction {
  const ExecutedAction({
    required this.toolName,
    required this.args,
    required this.result,
  });

  /// Fully-qualified tool name (`<namespace>.<tool>`).
  final String toolName;

  /// Arguments the harness invoked the tool with.
  final Map<String, Object?> args;

  /// Outcome reported by the tool.
  final ToolResult result;
}
