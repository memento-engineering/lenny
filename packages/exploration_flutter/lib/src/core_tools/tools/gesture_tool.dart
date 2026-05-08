import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';

import '../../contract/types.dart';
import '../core_plugin.dart';
import '../dispatch.dart';

const Set<String> _kKinds = <String>{
  'pan',
  'swipe',
  'pinch_in',
  'pinch_out',
};
const Set<String> _kDirs = <String>{'up', 'down', 'left', 'right'};

/// `core.gesture` — discrete-kind gesture dispatch. Schema rejects any
/// kind not in the enum at the validator step.
class GestureTool extends CoreTool {
  GestureTool(super.plugin);

  @override
  String get name => 'gesture';

  @override
  String get description =>
      'Perform a discrete gesture (pan, swipe, pinch_in, pinch_out) at a '
      'target semantics node.';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'node_id': <String, Object?>{'type': 'integer', 'minimum': 1},
          'kind': <String, Object?>{
            'type': 'string',
            'enum': <String>['pan', 'swipe', 'pinch_in', 'pinch_out'],
          },
          'direction': <String, Object?>{
            'type': 'string',
            'enum': <String>['up', 'down', 'left', 'right'],
          },
          'distance_px': <String, Object?>{
            'type': 'number',
            'minimum': 10,
            'maximum': 1000,
          },
          'scale': <String, Object?>{
            'type': 'number',
            'minimum': 0.1,
            'maximum': 5.0,
          },
        },
        'required': <String>['node_id', 'kind'],
        'additionalProperties': false,
      });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    final ToolResult? term = terminatedGuard();
    if (term != null) return term;
    final ToolResult? a = requireField(args, 'node_id', int);
    if (a != null) return a;
    final ToolResult? b = requireField(args, 'kind', String);
    if (b != null) return b;
    final int id = args['node_id']! as int;
    final String kind = args['kind']! as String;
    if (!_kKinds.contains(kind)) {
      return ToolResult(
        ok: false,
        error: '${CoreToolErrorCode.schemaViolation}: kind must be one of '
            '${_kKinds.toList()}',
      );
    }

    // Validate kind-specific schema BEFORE looking up the node so a
    // schema_violation always wins over target_not_found.
    String? dir;
    double dist = 0;
    double scale = 0;
    switch (kind) {
      case 'pan':
      case 'swipe':
        final ToolResult? cd = requireField(args, 'direction', String);
        if (cd != null) return cd;
        final ToolResult? cdist =
            requireField(args, 'distance_px', num);
        if (cdist != null) return cdist;
        dir = args['direction']! as String;
        if (!_kDirs.contains(dir)) {
          return ToolResult(
            ok: false,
            error: '${CoreToolErrorCode.schemaViolation}: direction must '
                'be one of ${_kDirs.toList()}',
          );
        }
        dist = (args['distance_px']! as num).toDouble();
        if (dist < 10 || dist > 1000) {
          return ToolResult(
            ok: false,
            error: '${CoreToolErrorCode.schemaViolation}: distance_px '
                'must be 10..1000',
          );
        }
        break;
      case 'pinch_in':
      case 'pinch_out':
        scale = ((args['scale'] as num?) ?? (kind == 'pinch_in' ? 0.5 : 2.0))
            .toDouble();
        if (scale < 0.1 || scale > 5.0) {
          return ToolResult(
            ok: false,
            error:
                '${CoreToolErrorCode.schemaViolation}: scale must be 0.1..5.0',
          );
        }
        break;
    }

    final SemanticsNode? node = plugin.lookupNode(id);
    if (node == null) return targetNotFound(id);
    final Rect rect = globalRectOf(node);

    switch (kind) {
      case 'pan':
      case 'swipe':
        final Offset start = rect.center;
        final Offset end = _offsetFor(dir!, dist, start);
        // Drive a synchronous pointer chain (no inter-step delay) so the
        // gesture completes deterministically under flutter_test's
        // FakeAsync without requiring callers to pump time forward.
        await hitTestDrag(
          start,
          end,
          steps: kind == 'swipe' ? 4 : 8,
          stepDuration: Duration.zero,
        );
        return const ToolResult(ok: true, value: <String, Object?>{});

      case 'pinch_in':
      case 'pinch_out':
        final double startSpan =
            (rect.shortestSide / 4).clamp(20.0, 200.0).toDouble();
        final double endSpan = startSpan * scale;
        await hitTestPinch(
          rect.center,
          startSpan: startSpan,
          endSpan: endSpan,
          stepDuration: Duration.zero,
        );
        return const ToolResult(ok: true, value: <String, Object?>{});
    }
    // Unreachable — kind enum guards above.
    return ToolResult(
      ok: false,
      error: '${CoreToolErrorCode.dispatchFailed}: unhandled kind $kind',
    );
  }

  static Offset _offsetFor(String dir, double distance, Offset start) {
    switch (dir) {
      case 'up':
        return start.translate(0, -distance);
      case 'down':
        return start.translate(0, distance);
      case 'left':
        return start.translate(-distance, 0);
      case 'right':
        return start.translate(distance, 0);
    }
    return start;
  }
}
