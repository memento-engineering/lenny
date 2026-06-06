import 'package:flutter/semantics.dart';

import '../../contract/types.dart';
import '../core_plugin.dart';
import '../dispatch.dart';

/// `core.enter_text` — focuses the target then delivers [text] via
/// `SemanticsAction.setText`. Falls back to a synthesized tap when the
/// node does not advertise `focus`.
class EnterTextTool extends CoreTool {
  EnterTextTool(super.plugin);

  @override
  String get name => 'enter_text';

  @override
  String get description =>
      'Focus a target semantics node and replace its text contents.';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'node_id': <String, Object?>{'type': 'integer', 'minimum': 1},
          'text': <String, Object?>{
            'type': 'string',
            'maxLength': 4096,
          },
        },
        'required': <String>['node_id', 'text'],
        'additionalProperties': false,
      });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    final ToolResult? term = terminatedGuard();
    if (term != null) return term;
    final ToolResult? badId = requireField(args, 'node_id', int);
    if (badId != null) return badId;
    final ToolResult? badTxt = requireField(args, 'text', String);
    if (badTxt != null) return badTxt;
    final int id = args['node_id']! as int;
    final String text = args['text']! as String;
    if (text.length > 4096) {
      return ToolResult(
        ok: false,
        error:
            '${CoreToolErrorCode.schemaViolation}: text exceeds 4096 chars',
      );
    }
    final SemanticsNode? node = plugin.lookupNode(id);
    if (node == null) return targetNotFound(id);

    // Step 1: focus. Prefer SemanticsAction.focus, then tap fallback.
    final SemanticsData data = node.getSemanticsData();
    if ((data.actions & SemanticsAction.focus.index) != 0) {
      ownerPerformAction(node, SemanticsAction.focus);
    } else {
      await hitTestTap(logicalRectOf(node));
    }

    // Step 2: setText. Pass the text payload as the action argument.
    if ((data.actions & SemanticsAction.setText.index) != 0) {
      ownerPerformAction(node, SemanticsAction.setText, text);
    } else {
      return ToolResult(
        ok: false,
        error:
            '${CoreToolErrorCode.targetUnreachable}: node $id does not '
            'advertise SemanticsAction.setText',
      );
    }

    return const ToolResult(
      ok: true,
      value: <String, Object?>{},
    );
  }
}
