import 'package:flutter/semantics.dart';

import '../../contract/types.dart';
import '../dispatch.dart';

/// `core.tap` — taps the target semantics node by stable id.
///
/// Dispatch path: prefer `SemanticsAction.tap` when the node advertises
/// it; otherwise synthesize a touch press at the node's centre.
class TapTool extends CoreTool {
  TapTool(super.plugin);

  @override
  String get name => 'tap';

  @override
  String get description =>
      'Tap a target semantics node, identified by its stable id.';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'node_id': <String, Object?>{'type': 'integer', 'minimum': 1},
    },
    'required': <String>['node_id'],
    'additionalProperties': false,
  });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    final ToolResult? term = terminatedGuard();
    if (term != null) return term;
    final ToolResult? bad = requireField(args, 'node_id', int);
    if (bad != null) return bad;
    final int id = args['node_id']! as int;
    final SemanticsNode? node = plugin.lookupNode(id);
    if (node == null) return targetNotFound(id);
    return dispatchSemanticsActionOrFallback(
      node,
      SemanticsAction.tap,
      fallback: hitTestTap,
    );
  }
}

/// `core.long_press` — long-presses the target semantics node.
class LongPressTool extends CoreTool {
  LongPressTool(super.plugin);

  @override
  String get name => 'long_press';

  @override
  String get description =>
      'Long-press a target semantics node, identified by its stable id.';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'node_id': <String, Object?>{'type': 'integer', 'minimum': 1},
    },
    'required': <String>['node_id'],
    'additionalProperties': false,
  });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    final ToolResult? term = terminatedGuard();
    if (term != null) return term;
    final ToolResult? bad = requireField(args, 'node_id', int);
    if (bad != null) return bad;
    final int id = args['node_id']! as int;
    final SemanticsNode? node = plugin.lookupNode(id);
    if (node == null) return targetNotFound(id);
    return dispatchSemanticsActionOrFallback(
      node,
      SemanticsAction.longPress,
      fallback: hitTestLongPress,
    );
  }
}
