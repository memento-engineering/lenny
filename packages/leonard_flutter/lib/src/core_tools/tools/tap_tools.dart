import 'package:flutter/semantics.dart';

import '../../contract/types.dart';
import '../core_extension.dart';
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

/// `core.tap_at` — taps a normalized point inside a semantics node's rect.
///
/// Unlike [TapTool], this tool always uses coordinate hit-testing. The
/// required `x` and `y` arguments are inclusive fractions of the target
/// node's logical width and height.
class TapAtTool extends CoreTool {
  TapAtTool(super.plugin);

  @override
  String get name => 'tap_at';

  @override
  String get description =>
      'Tap a normalized point inside a target semantics node.';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'node_id': <String, Object?>{'type': 'integer', 'minimum': 1},
      'x': <String, Object?>{'type': 'number', 'minimum': 0, 'maximum': 1},
      'y': <String, Object?>{'type': 'number', 'minimum': 0, 'maximum': 1},
    },
    'required': <String>['node_id', 'x', 'y'],
    'additionalProperties': false,
  });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    final ToolResult? term = terminatedGuard();
    if (term != null) return term;
    final ToolResult? badId = requireField(args, 'node_id', int);
    if (badId != null) return badId;
    final ToolResult? badX = requireField(args, 'x', num);
    if (badX != null) return badX;
    final ToolResult? badY = requireField(args, 'y', num);
    if (badY != null) return badY;

    final double x = (args['x']! as num).toDouble();
    final double y = (args['y']! as num).toDouble();
    if (!x.isFinite || x < 0 || x > 1) {
      return ToolResult(
        ok: false,
        error:
            '${CoreToolErrorCode.schemaViolation}: x must be finite and in '
            'the inclusive range 0..1',
      );
    }
    if (!y.isFinite || y < 0 || y > 1) {
      return ToolResult(
        ok: false,
        error:
            '${CoreToolErrorCode.schemaViolation}: y must be finite and in '
            'the inclusive range 0..1',
      );
    }

    final int id = args['node_id']! as int;
    final SemanticsNode? node = plugin.lookupNode(id);
    if (node == null) return targetNotFound(id);

    final Rect rect = logicalRectOf(node);
    final Offset point = Offset(
      rect.left + rect.width * x,
      rect.top + rect.height * y,
    );
    await hitTestTap(Rect.fromCenter(center: point, width: 0, height: 0));
    return const ToolResult(ok: true, value: <String, Object?>{});
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
