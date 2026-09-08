import '../../contract/types.dart';
import '../dispatch.dart';

/// `core.recall` — reads an exact string from the session scratchpad.
class RecallTool extends CoreTool {
  /// Creates a recall tool backed directly by [scratchpad].
  RecallTool(super.plugin, Map<String, String> scratchpad)
    : _scratchpad = scratchpad;

  final Map<String, String> _scratchpad;

  @override
  String get name => 'recall';

  @override
  String get description =>
      'Recall the exact string remembered under a non-empty session key.';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
    r'$schema': 'http://json-schema.org/draft-07/schema#',
    'type': 'object',
    'properties': <String, Object?>{
      'key': <String, Object?>{'type': 'string', 'minLength': 1},
    },
    'required': <String>['key'],
    'additionalProperties': false,
  });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    final ToolResult? term = terminatedGuard();
    if (term != null) return term;
    final ToolResult? badKey = requireField(args, 'key', String);
    if (badKey != null) return badKey;
    final String key = args['key']! as String;
    if (key.isEmpty) {
      return const ToolResult(
        ok: false,
        error: 'schema_violation: key must be non-empty',
      );
    }
    final String? stored = _scratchpad[key];
    if (stored == null) {
      return ToolResult(
        ok: false,
        error: 'target_not_found: no remembered value for key "$key"',
      );
    }
    return ToolResult(ok: true, value: <String, Object?>{'value': stored});
  }
}
