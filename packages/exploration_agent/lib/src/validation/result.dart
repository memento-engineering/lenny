/// Result types for [ActionValidator].
///
/// Web-compatible: pure Dart, no `dart:io`.
library;

import 'dart:convert';

/// Outcome of validating a candidate action against the merged tool list
/// and the current observation.
///
/// Sealed: either a [ValidationOk] (action is well-formed and references
/// live UI) or a [ValidationReject] carrying a structured, model-readable
/// reason. PRD §10 step 7, §17.
sealed class ValidationResult {
  const ValidationResult();
}

/// The candidate action passed all three validation passes.
class ValidationOk extends ValidationResult {
  const ValidationOk();

  @override
  bool operator ==(Object other) => other is ValidationOk;

  @override
  int get hashCode => 0;
}

/// The candidate action was rejected by one of the three passes.
///
/// Field meanings:
/// - [tool] — the tool name from the rejected action (echoed for clarity).
/// - [reason] — one of: `unknown_tool`, `schema_invalid`, `node_not_found`,
///   `node_disabled`. The loop driver routes on this string.
/// - [expected] — for `unknown_tool`, the list of available tool names.
/// - [got] — what the action actually carried (e.g. the unknown tool name,
///   or the offending node id).
/// - [pointer] — JSON Pointer to the bad field (e.g. `/node_id`,
///   `/scrollable_id`, or a sub-pointer inside `args` for schema
///   violations). Null when not applicable.
/// - [description] — short, single-line human description suitable for
///   splicing into a retry prompt.
class ValidationReject extends ValidationResult {
  const ValidationReject({
    required this.tool,
    required this.reason,
    this.expected,
    this.got,
    this.pointer,
    this.description,
  });

  /// Tool name from the rejected action.
  final String tool;

  /// Rejection reason — one of: `unknown_tool`, `schema_invalid`,
  /// `node_not_found`, `node_disabled`.
  final String reason;

  /// Expected values (e.g. list of available tool names for
  /// `unknown_tool`). Null when not applicable.
  final List<String>? expected;

  /// What the action actually carried (e.g. the unknown tool name, or
  /// the node id that didn't resolve). Null when not applicable.
  final Object? got;

  /// JSON Pointer to the bad field. Null when not applicable.
  final String? pointer;

  /// One-line human description suitable for retry-prompt splicing.
  final String? description;

  /// Encode as a single-line JSON string for the loop driver to splice
  /// into the model's retry prompt. Keys with null values are omitted.
  String toModelMessage() {
    final m = <String, Object?>{
      'tool': tool,
      'reason': reason,
      if (expected != null) 'expected': expected,
      if (got != null) 'got': got,
      if (pointer != null) 'pointer': pointer,
      if (description != null) 'description': description,
    };
    return jsonEncode(m);
  }

  @override
  bool operator ==(Object other) =>
      other is ValidationReject &&
      tool == other.tool &&
      reason == other.reason &&
      _listEq(expected, other.expected) &&
      got == other.got &&
      pointer == other.pointer &&
      description == other.description;

  @override
  int get hashCode => Object.hash(
        tool,
        reason,
        expected == null ? null : Object.hashAll(expected!),
        got,
        pointer,
        description,
      );
}

bool _listEq(List<String>? a, List<String>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
