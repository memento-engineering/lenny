import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/semantics.dart';

import '../contract/plugin.dart';
import '../contract/plugin_context.dart';
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
  /// shape consumed by the cx6.14 action validator.
  ToolResult toToolResult() =>
      ToolResult(ok: false, error: '$code: $message');

  @override
  String toString() => 'CoreToolError($code): $message';
}

/// Host-installed plugin contributing the 10 `core.*` action tools
/// (PRD §12.1).
///
/// The binding registers a single instance of [CorePlugin] BEFORE any
/// user-supplied plugin, which both (a) exposes the tools at
/// `ext.flutter.exploration.core.<tool>` and (b) reserves the `core`
/// namespace via [PluginRegistry]'s existing duplicate-namespace check
/// (any user plugin claiming `core` will fail to register and be
/// skipped).
class CorePlugin extends ExplorationPlugin {
  CorePlugin({required SemanticsCapture semantics})
      : _semantics = semantics;

  final SemanticsCapture _semantics;

  /// Built lazily on first access; cached so [tools] returns the same
  /// list across calls.
  List<ExplorationTool>? _toolsCache;

  /// Latched once [DoneTool] runs successfully. Subsequent invocations of
  /// [_CoreTool] subclasses short-circuit with `session_terminated`.
  bool _terminated = false;

  /// Whether [DoneTool] has run; surfaced for the loop driver (cx6.18)
  /// and consumed by [CoreTool.terminatedGuard].
  bool get terminated => _terminated;

  /// Internal: invoked by [DoneTool.call].
  void markTerminated() {
    _terminated = true;
  }

  /// Internal: lookup a live [SemanticsNode] by stable id, or null.
  SemanticsNode? lookupNode(int stableId) => _semantics.lookup(stableId);

  /// Internal: snapshot the current semantics tree (used by
  /// [ScrollUntilVisibleTool] and [InspectWidgetTool]).
  List<Map<String, Object>> snapshotSemantics() => _semantics.capture();

  @override
  String get namespace => 'core';

  @override
  List<ExplorationTool> get tools {
    return _toolsCache ??= <ExplorationTool>[
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
  Future<void> initialize(PluginContext ctx) async {
    for (final ExplorationTool tool in tools) {
      ctx.registerExtension(tool.name, (
        String method,
        Map<String, String> params,
      ) async {
        try {
          final Map<String, Object?> args = _decodeParams(params);
          final ToolResult r = await tool.call(args);
          return developer.ServiceExtensionResponse.result(
            jsonEncode(<String, Object?>{
              'ok': r.ok,
              'value': r.value,
              'error': r.error,
            }),
          );
        } catch (e, st) {
          // The tool itself should never throw — every error path returns
          // a ToolResult. Defence-in-depth: wrap an unexpected throw into
          // `dispatch_failed` so the agent sees a structured error.
          return developer.ServiceExtensionResponse.result(
            jsonEncode(<String, Object?>{
              'ok': false,
              'value': null,
              'error':
                  '${CoreToolErrorCode.dispatchFailed}: $e',
              'trace': st.toString(),
            }),
          );
        }
      });
    }
  }

  @override
  Future<Map<String, Object?>?> observe(ObservationContext ctx) async => null;

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
Map<String, Object?> _decodeParams(Map<String, String> params) {
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
