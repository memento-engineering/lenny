import 'dart:async';
import 'dart:convert';

import 'package:flutter/semantics.dart';

import '../contract/extension.dart';
import '../contract/extension_context.dart';
import '../contract/types.dart';
import '../semantics/semantics_capture.dart';
import 'core_tools.dart';

/// Stable error codes returned by core tools as the prefix of
/// [ToolResult.error]. The format is `'<code>: <human message>'`.
abstract class CoreToolErrorCode {
  static const String targetNotFound = 'target_not_found';
  static const String targetUnreachable = 'target_unreachable';
  static const String schemaViolation = 'schema_violation';
  static const String sessionTerminated = 'session_terminated';
  static const String systemBackFailed = 'system_back_failed';
  static const String dispatchFailed = 'dispatch_failed';
}

/// Helper exception type for core-tool error reporting.
///
/// Tools never throw this directly to the registry — they convert to a
/// [ToolResult] via [toToolResult] so the harness sees the structured
/// error payload (PRD §12.1).
class CoreToolError implements Exception {
  CoreToolError(this.code, this.message);

  /// One of the [CoreToolErrorCode] constants.
  final String code;

  /// Human-readable message; surfaced to the agent.
  final String message;

  /// Convert to the standard `ToolResult(ok: false, error: '<code>: <msg>')`
  /// shape consumed by the action validator.
  ToolResult toToolResult() => ToolResult(ok: false, error: '$code: $message');

  @override
  String toString() => 'CoreToolError($code): $message';
}

/// Host-installed extension contributing the 10 `core.*` action tools
/// (PRD §12.1).
///
/// The binding registers a single instance of [CoreExtension] BEFORE any
/// user-supplied extension, which both (a) exposes the tools at
/// `ext.exploration.core.<tool>` and (b) reserves the `core`
/// namespace via [ExtensionRegistry]'s existing duplicate-namespace check
/// (any user extension claiming `core` will fail to register and be
/// skipped).
class CoreExtension extends LeonardExtension {
  CoreExtension({required SemanticsCapture semantics}) : _semantics = semantics;

  final SemanticsCapture _semantics;

  /// Built lazily on first access; cached so [tools] returns the same
  /// list across calls.
  List<LeonardTool>? _toolsCache;

  /// Latched once [DoneTool] runs successfully. Subsequent invocations of
  /// [_CoreTool] subclasses short-circuit with `session_terminated`.
  bool _terminated = false;

  /// Whether [DoneTool] has run; surfaced for the loop driver
  /// and consumed by [CoreTool.terminatedGuard].
  bool get terminated => _terminated;

  /// Internal: invoked by [DoneTool.call].
  void markTerminated() {
    _terminated = true;
  }

  /// Clears the terminal latch so a fresh agent session can act again.
  ///
  /// Invoked by the binding's `core.handshake` handler. A handshake marks
  /// the start of a new agent session; without this reset the `_terminated`
  /// flag set by a prior [DoneTool] persists for the life of the app
  /// process, so any *subsequent* drive against the same running app
  /// short-circuits every action with `session_terminated`. Safe because
  /// the handshake runs before any action and the loop stops at `done`, so
  /// no in-flight session is ever un-terminated mid-run.
  void resetTermination() {
    _terminated = false;
  }

  /// Internal: lookup a live [SemanticsNode] by stable id, or null.
  SemanticsNode? lookupNode(int stableId) => _semantics.lookup(stableId);

  /// Async snapshot; awaits the first semantics frame when needed.
  /// Use this instead of [snapshotSemantics] at all production call sites.
  Future<List<Map<String, Object>>> snapshotSemanticsAsync() =>
      _semantics.captureAsync();

  /// Deprecated synchronous snapshot. Races initial semantics flush on device.
  @Deprecated(
    'Use snapshotSemanticsAsync() — this form returns [] on first call on '
    'a real device before the semantics tree is materialized. '
    'Will be removed when all call sites are migrated.',
  )
  List<Map<String, Object>> snapshotSemantics() => _semantics.capture();

  @override
  String get namespace => 'core';

  @override
  List<LeonardTool> get tools {
    return _toolsCache ??= <LeonardTool>[
      TapTool(this),
      LongPressTool(this),
      EnterTextTool(this),
      ScrollTool(this),
      ScrollUntilVisibleTool(this),
      GestureTool(this),
      SystemBackTool(this),
      WaitTool(this),
      InspectWidgetTool(this),
      DoneTool(this),
    ];
  }

  @override
  Future<void> initialize(ExtensionContext ctx) async {
    // Tool VM-service extensions are registered by the binding
    // (LeonardBinding._registerExtensionToolExtensions) after all
    // extensions have initialized. CoreExtension no longer registers here
    // to prevent double-registration — developer.registerExtension
    // throws on duplicate names (dart:developer contract).
  }

  @override
  Future<BusyState> busyState() async => BusyState.idle;

  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}

  @override
  Future<void> dispose() async {}
}

/// VM service extensions hand parameters as `Map<String, String>` (every
/// value JSON-encoded). Decode each value back into its native form so
/// tools can apply `JsonSchema` validation against the original types.
///
/// Promoted from the private `_decodeParams` so the binding's
/// `@visibleForTesting invokeExtensionTool` helper can share the decode path
/// with `CoreExtension.initialize`.
Map<String, Object?> decodeServiceExtensionParams(Map<String, String> params) {
  final Map<String, Object?> out = <String, Object?>{};
  params.forEach((String k, String v) {
    out[k] = _tryDecode(v);
  });
  return out;
}

Object? _tryDecode(String raw) {
  // Strings round-trip through JSON as quoted strings — try JSON first;
  // fall back to the raw string when the input isn't valid JSON.
  try {
    return jsonDecode(raw);
  } catch (_) {
    return raw;
  }
}

/// Run [tool] with [args] and wrap the result in the canonical
/// `{ok, value, error[, trace]}` envelope.
///
/// Single source of truth for that envelope shape — used by both
/// `CoreExtension.initialize`'s per-tool extension handler and the binding's
/// `@visibleForTesting invokeExtensionTool` helper. Never throws: any
/// unexpected error becomes a `dispatch_failed` envelope.
Future<String> dispatchToolToEnvelope(
  LeonardTool tool,
  Map<String, Object?> args,
) async {
  try {
    final ToolResult r = await tool.call(args);
    return jsonEncode(<String, Object?>{
      'ok': r.ok,
      'value': r.value,
      'error': r.error,
    });
  } catch (e, st) {
    return jsonEncode(<String, Object?>{
      'ok': false,
      'value': null,
      'error': '${CoreToolErrorCode.dispatchFailed}: $e',
      'trace': st.toString(),
    });
  }
}
