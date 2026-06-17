import 'dart:convert';

import 'extension.dart';
import 'types.dart';

/// Error-code prefix used when [dispatchToolToEnvelope] catches an
/// unexpected throw. Mirrors `CoreToolErrorCode.dispatchFailed` in
/// `leonard_flutter` (kept in sync by value).
const String _kDispatchFailed = 'dispatch_failed';

/// VM service extensions hand parameters as `Map<String, String>` (every
/// value JSON-encoded). Decode each value back into its native form so
/// tools can apply `JsonSchema` validation against the original types.
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
/// Single source of truth for that envelope shape — used by both the
/// Flutter binding's per-tool extension handler and the pure-Dart host.
/// Never throws: any unexpected error becomes a `dispatch_failed` envelope.
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
      'error': '$_kDispatchFailed: $e',
      'trace': st.toString(),
    });
  }
}
