import '../../contract/types.dart';
import '../dispatch.dart';

/// `core.remember` — stores an exact string in the session scratchpad.
class RememberTool extends CoreTool {
  /// Creates a remember tool backed directly by [scratchpad].
  RememberTool(super.plugin, Map<String, String> scratchpad)
    : _scratchpad = scratchpad;

  final Map<String, String> _scratchpad;

  @override
  String get name => 'remember';

  @override
  String get description =>
      'Remember an exact string under a non-empty key for this session.';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
    r'$schema': 'http://json-schema.org/draft-07/schema#',
    'type': 'object',
    'properties': <String, Object?>{
      'key': <String, Object?>{'type': 'string', 'minLength': 1},
      'value': <String, Object?>{'type': 'string', 'minLength': 1},
    },
    'required': <String>['key', 'value'],
    'additionalProperties': false,
  });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    final ToolResult? term = terminatedGuard();
    if (term != null) return term;
    final ToolResult? badKey = requireField(args, 'key', String);
    if (badKey != null) return badKey;
    final ToolResult? badValue = requireField(args, 'value', String);
    if (badValue != null) return badValue;
    final String key = args['key']! as String;
    final String value = args['value']! as String;
    if (key.isEmpty) {
      return const ToolResult(
        ok: false,
        error: 'schema_violation: key must be non-empty',
      );
    }
    if (value.isEmpty) {
      return const ToolResult(
        ok: false,
        error: 'schema_violation: value must be non-empty',
      );
    }
    _scratchpad[key] = value;
    return const ToolResult(ok: true, value: <String, Object?>{});
  }
}
