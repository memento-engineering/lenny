import '../../contract/types.dart';
import '../core_plugin.dart';
import '../dispatch.dart';

/// `core.wait` — pauses the session for a bounded duration. Schema
/// rejects values <= 0 or > 5 seconds.
class WaitTool extends CoreTool {
  WaitTool(super.plugin);

  @override
  String get name => 'wait';

  @override
  String get description =>
      'Wait for a bounded number of seconds (0 < seconds <= 5).';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'seconds': <String, Object?>{
            'type': 'number',
            'exclusiveMinimum': 0,
            'maximum': 5,
          },
        },
        'required': <String>['seconds'],
        'additionalProperties': false,
      });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    final ToolResult? term = terminatedGuard();
    if (term != null) return term;
    final ToolResult? bad = requireField(args, 'seconds', num);
    if (bad != null) return bad;
    final double seconds = (args['seconds']! as num).toDouble();
    if (!seconds.isFinite || seconds <= 0 || seconds > 5) {
      return ToolResult(
        ok: false,
        error: '${CoreToolErrorCode.schemaViolation}: seconds must be in '
            '(0, 5]',
      );
    }
    await Future<void>.delayed(
      Duration(microseconds: (seconds * 1e6).round()),
    );
    return const ToolResult(ok: true, value: <String, Object?>{});
  }
}
