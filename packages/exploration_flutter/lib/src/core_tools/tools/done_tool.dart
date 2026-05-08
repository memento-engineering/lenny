import '../../contract/types.dart';
import '../core_plugin.dart';
import '../dispatch.dart';

/// `core.done` — terminal tool. Records a structured `{type:'done',
/// reason}` value and latches the session-terminated flag so any
/// subsequent action call short-circuits with `session_terminated`.
class DoneTool extends CoreTool {
  DoneTool(super.plugin);

  @override
  String get name => 'done';

  @override
  String get description =>
      'Mark the session as complete with a free-form reason.';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'reason': <String, Object?>{
            'type': 'string',
            'maxLength': 512,
          },
        },
        'required': <String>['reason'],
        'additionalProperties': false,
      });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    // NOTE: DoneTool deliberately does NOT call terminatedGuard — calling
    // done twice should still return the canonical terminal record (it's
    // idempotent), not a session_terminated error.
    final ToolResult? bad = requireField(args, 'reason', String);
    if (bad != null) return bad;
    final String reason = args['reason']! as String;
    if (reason.length > 512) {
      return ToolResult(
        ok: false,
        error:
            '${CoreToolErrorCode.schemaViolation}: reason exceeds 512 chars',
      );
    }
    plugin.markTerminated();
    return ToolResult(
      ok: true,
      value: <String, Object?>{
        'type': 'done',
        'reason': reason,
      },
    );
  }
}
