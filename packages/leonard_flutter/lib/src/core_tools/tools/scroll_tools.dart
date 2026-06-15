import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';

import '../../contract/types.dart';
import '../core_extension.dart';
import '../dispatch.dart';

const Set<String> _kAxes = <String>{'vertical', 'horizontal'};

/// `core.scroll` — scrolls a target scrollable by a signed pixel delta.
///
/// Dispatch path: prefer the matching `SemanticsAction.scrollUp/Down/Left/
/// Right` when the node advertises it, else pointer-drag fallback at the
/// node's centre rect.
class ScrollTool extends CoreTool {
  ScrollTool(super.plugin);

  @override
  String get name => 'scroll';

  @override
  String get description =>
      'Scroll a target scrollable by a signed pixel delta along an axis.';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'node_id': <String, Object?>{'type': 'integer', 'minimum': 1},
          'axis': <String, Object?>{
            'type': 'string',
            'enum': <String>['vertical', 'horizontal'],
          },
          'delta_pixels': <String, Object?>{
            'type': 'number',
            'minimum': -10000,
            'maximum': 10000,
          },
        },
        'required': <String>['node_id', 'axis', 'delta_pixels'],
        'additionalProperties': false,
      });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    final ToolResult? term = terminatedGuard();
    if (term != null) return term;
    final ToolResult? a = requireField(args, 'node_id', int);
    if (a != null) return a;
    final ToolResult? b = requireField(args, 'axis', String);
    if (b != null) return b;
    final ToolResult? c = requireField(args, 'delta_pixels', num);
    if (c != null) return c;
    final int id = args['node_id']! as int;
    final String axis = args['axis']! as String;
    if (!_kAxes.contains(axis)) {
      return ToolResult(
        ok: false,
        error: '${CoreToolErrorCode.schemaViolation}: axis must be one of '
            '${_kAxes.toList()}',
      );
    }
    final double delta = (args['delta_pixels']! as num).toDouble();
    final SemanticsNode? node = plugin.lookupNode(id);
    if (node == null) return targetNotFound(id);

    final SemanticsAction action = _actionFor(axis: axis, delta: delta);
    return dispatchSemanticsActionOrFallback(
      node,
      action,
      fallback: (Rect rect) => _dragFallback(rect, axis: axis, delta: delta),
    );
  }

  static SemanticsAction _actionFor({
    required String axis,
    required double delta,
  }) {
    if (axis == 'vertical') {
      return delta > 0 ? SemanticsAction.scrollUp : SemanticsAction.scrollDown;
    }
    return delta > 0
        ? SemanticsAction.scrollLeft
        : SemanticsAction.scrollRight;
  }

  static Future<void> _dragFallback(
    Rect rect, {
    required String axis,
    required double delta,
  }) async {
    final Offset centre = rect.center;
    final Offset start = centre;
    // Drag in the OPPOSITE direction to bring delta_pixels of content
    // into view (touchscreen convention: pull content up to scroll up).
    final Offset end = axis == 'vertical'
        ? centre.translate(0, -delta)
        : centre.translate(-delta, 0);
    await hitTestDrag(start, end, stepDuration: Duration.zero);
  }
}

/// `core.scroll_until_visible` — repeatedly scrolls until the target node
/// appears in the captured semantics tree, or returns `target_unreachable`
/// after the configured cap.
class ScrollUntilVisibleTool extends CoreTool {
  ScrollUntilVisibleTool(super.plugin);

  @override
  String get name => 'scroll_until_visible';

  @override
  String get description =>
      'Scroll a scrollable until the target node appears in semantics, '
      'capped at max_iterations.';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'scrollable_id': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
          },
          'target_id': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
          },
          'axis': <String, Object?>{
            'type': 'string',
            'enum': <String>['vertical', 'horizontal'],
          },
          'max_iterations': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 50,
          },
          'step_pixels': <String, Object?>{
            'type': 'number',
            'minimum': -10000,
            'maximum': 10000,
          },
        },
        'required': <String>['scrollable_id', 'target_id', 'axis'],
        'additionalProperties': false,
      });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    final ToolResult? term = terminatedGuard();
    if (term != null) return term;
    final ToolResult? a = requireField(args, 'scrollable_id', int);
    if (a != null) return a;
    final ToolResult? b = requireField(args, 'target_id', int);
    if (b != null) return b;
    final ToolResult? c = requireField(args, 'axis', String);
    if (c != null) return c;
    final ToolResult? d =
        requireField(args, 'max_iterations', int, optional: true);
    if (d != null) return d;
    final ToolResult? e =
        requireField(args, 'step_pixels', num, optional: true);
    if (e != null) return e;

    final int scrollableId = args['scrollable_id']! as int;
    final int targetId = args['target_id']! as int;
    final String axis = args['axis']! as String;
    if (!_kAxes.contains(axis)) {
      return ToolResult(
        ok: false,
        error: '${CoreToolErrorCode.schemaViolation}: axis must be one of '
            '${_kAxes.toList()}',
      );
    }
    final int maxIters = (args['max_iterations'] as int?) ?? 20;
    if (maxIters < 1 || maxIters > 50) {
      return ToolResult(
        ok: false,
        error:
            '${CoreToolErrorCode.schemaViolation}: max_iterations must be '
            '1..50',
      );
    }
    final double step = ((args['step_pixels'] as num?) ?? 200).toDouble();

    for (int i = 0; i < maxIters; i++) {
      // Re-walk semantics; if target is present, we're done.
      final List<Map<String, Object>> recs = await plugin.snapshotSemanticsAsync();
      final bool present = recs.any(
        (Map<String, Object> r) => (r['id'] as int) == targetId,
      );
      if (present) {
        return ToolResult(
          ok: true,
          value: <String, Object?>{'iterations': i},
        );
      }
      final SemanticsNode? scrollable = plugin.lookupNode(scrollableId);
      if (scrollable == null) return targetNotFound(scrollableId);
      final SemanticsAction action = ScrollTool._actionFor(
        axis: axis,
        delta: step,
      );
      await dispatchSemanticsActionOrFallback(
        scrollable,
        action,
        fallback: (Rect rect) =>
            ScrollTool._dragFallback(rect, axis: axis, delta: step),
      );
    }
    return ToolResult(
      ok: false,
      error: '${CoreToolErrorCode.targetUnreachable}: node $targetId not '
          'visible after $maxIters scroll iterations',
    );
  }
}
