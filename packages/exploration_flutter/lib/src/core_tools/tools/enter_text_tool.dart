import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import '../../contract/types.dart';
import '../core_plugin.dart';
import '../dispatch.dart';
import '../editable_resolver.dart';

class EnterTextTool extends CoreTool {
  EnterTextTool(super.plugin);

  @override
  String get name => 'enter_text';

  @override
  String get description =>
      'Resolve the EditableText widget under the target semantics node '
      'and set its controller value directly.';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'node_id': <String, Object?>{'type': 'integer', 'minimum': 1},
      'text': <String, Object?>{'type': 'string', 'maxLength': 4096},
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
        error: '${CoreToolErrorCode.schemaViolation}: text exceeds 4096 chars',
      );
    }
    final SemanticsNode? node = plugin.lookupNode(id);
    if (node == null) return targetNotFound(id);

    final Rect physicalRect = globalRectOf(node);
    final EditableTextState? editable = resolveEditableText(physicalRect);
    if (editable == null) {
      return ToolResult(
        ok: false,
        error:
            '${CoreToolErrorCode.targetUnreachable}: node $id has no '
            'matching EditableText in the widget tree',
      );
    }
    editable.widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    return const ToolResult(ok: true, value: <String, Object?>{});
  }
}
