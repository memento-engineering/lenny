import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../contract/extension.dart';
import '../contract/types.dart';
import 'core_extension.dart';

/// Shared base for every `core.*` tool that holds a back-pointer to the
/// owning [CoreExtension] (so it can read the terminated flag and look up
/// semantics nodes).
abstract class CoreTool extends LeonardTool {
  CoreTool(this.plugin);

  final CoreExtension plugin;

  /// Returns a `session_terminated` [ToolResult] when [DoneTool] has
  /// already run, otherwise `null`. Tools that should be rejected after
  /// session termination begin with
  /// `final ToolResult? t = terminatedGuard(); if (t != null) return t;`.
  ToolResult? terminatedGuard() {
    if (!plugin.terminated) return null;
    return ToolResult(
      ok: false,
      error:
          '${CoreToolErrorCode.sessionTerminated}: terminal action issued',
    );
  }
}

/// Compute the device-coordinate rect of [node] (its `rect` is in the
/// node's local coordinate space; transforms accumulate as we walk the
/// parent chain).
Rect globalRectOf(SemanticsNode node) {
  Matrix4 m = node.transform?.clone() ?? Matrix4.identity();
  SemanticsNode? cur = node.parent;
  while (cur != null) {
    if (cur.transform != null) {
      m = cur.transform!.clone()..multiply(m);
    }
    cur = cur.parent;
  }
  return MatrixUtils.transformRect(m, node.rect);
}

/// Convert the physical-pixel global rect of [node] to logical pixels by
/// dividing by the view's [devicePixelRatio].
///
/// [globalRectOf] walks the full semantics parent chain, which includes the
/// semantics-root DPR transform, so it returns physical pixels. Synthesized
/// [PointerEvent.position] values are interpreted as logical pixels by
/// [GestureBinding] (the engine divides by DPR before delivery). All
/// pointer-synthesis call sites must use this function, not [globalRectOf].
Rect logicalRectOf(SemanticsNode node) {
  final double dpr =
      WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
  final Rect physical = globalRectOf(node);
  return Rect.fromLTRB(
    physical.left / dpr,
    physical.top / dpr,
    physical.right / dpr,
    physical.bottom / dpr,
  );
}

/// Dispatch [action] on [node] via its [SemanticsOwner.performAction].
/// Returns `false` if the node has no live owner (e.g. detached).
bool ownerPerformAction(
  SemanticsNode node,
  SemanticsAction action, [
  Object? args,
]) {
  final SemanticsOwner? owner = node.owner;
  if (owner == null) return false;
  owner.performAction(node.id, action, args);
  return true;
}

/// Dispatch a [SemanticsAction] on [node] when the node advertises it,
/// otherwise call [fallback] with the node's global rect. Always returns
/// `ToolResult(ok: true)` on success — error mapping happens at the call
/// site.
Future<ToolResult> dispatchSemanticsActionOrFallback(
  SemanticsNode node,
  SemanticsAction action, {
  Object? actionArgs,
  required Future<void> Function(Rect rect) fallback,
}) async {
  final SemanticsData data = node.getSemanticsData();
  final bool advertises = (data.actions & action.index) != 0;
  if (advertises) {
    final bool dispatched = ownerPerformAction(node, action, actionArgs);
    if (dispatched) {
      return const ToolResult(ok: true, value: <String, Object?>{});
    }
    // No owner — fall through to hit-test.
  }
  await fallback(logicalRectOf(node));
  return const ToolResult(ok: true, value: <String, Object?>{});
}

/// Pointer id namespace for synthesized core-tool events. Starts high to
/// avoid collisions with framework-driven device pointers.
int _nextPointer = 0x70000000;
int _allocPointer() => _nextPointer++;

/// Dispatch a synthesized tap (`down` then `up`) at [rect.center].
Future<void> hitTestTap(Rect rect) =>
    _hitTestPress(rect, hold: Duration.zero);

/// Dispatch a synthesized long-press (down, 600ms hold, up) at
/// [rect.center].
Future<void> hitTestLongPress(Rect rect) => _hitTestPress(
      rect,
      hold: const Duration(milliseconds: 600),
    );

Future<void> _hitTestPress(Rect rect, {required Duration hold}) async {
  final Offset c = rect.center;
  final int pointer = _allocPointer();
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(
      pointer: pointer,
      position: c,
      kind: PointerDeviceKind.touch,
    ),
  );
  if (hold > Duration.zero) {
    await Future<void>.delayed(hold);
  }
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(
      pointer: pointer,
      position: c,
      kind: PointerDeviceKind.touch,
    ),
  );
}

/// Synthesize a pointer drag from [start] to [end] using [steps]
/// intermediate move events. Used as the pointer-fallback path for
/// scroll, swipe, and pan.
Future<void> hitTestDrag(
  Offset start,
  Offset end, {
  int steps = 8,
  Duration stepDuration = const Duration(milliseconds: 8),
}) async {
  final int pointer = _allocPointer();
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(
      pointer: pointer,
      position: start,
      kind: PointerDeviceKind.touch,
    ),
  );
  for (int i = 1; i <= steps; i++) {
    final double t = i / steps;
    final Offset p = Offset.lerp(start, end, t)!;
    GestureBinding.instance.handlePointerEvent(
      PointerMoveEvent(
        pointer: pointer,
        position: p,
        delta: p - Offset.lerp(start, end, (i - 1) / steps)!,
        kind: PointerDeviceKind.touch,
      ),
    );
    if (stepDuration > Duration.zero) {
      await Future<void>.delayed(stepDuration);
    }
  }
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(
      pointer: pointer,
      position: end,
      kind: PointerDeviceKind.touch,
    ),
  );
}

/// Synthesize a two-finger pinch centred at [center] going from
/// [startSpan] to [endSpan] (radial distance from centre to each
/// pointer). Positive `endSpan > startSpan` zooms in (`pinch_out`);
/// `endSpan < startSpan` zooms out (`pinch_in`).
Future<void> hitTestPinch(
  Offset center, {
  required double startSpan,
  required double endSpan,
  int steps = 8,
  Duration stepDuration = const Duration(milliseconds: 8),
}) async {
  final int p0 = _allocPointer();
  final int p1 = _allocPointer();
  Offset posAt(int p, double span) => p == p0
      ? center.translate(-span, 0)
      : center.translate(span, 0);

  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(
      pointer: p0,
      position: posAt(p0, startSpan),
      kind: PointerDeviceKind.touch,
    ),
  );
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(
      pointer: p1,
      position: posAt(p1, startSpan),
      kind: PointerDeviceKind.touch,
    ),
  );
  Offset prev0 = posAt(p0, startSpan);
  Offset prev1 = posAt(p1, startSpan);
  for (int i = 1; i <= steps; i++) {
    final double t = i / steps;
    final double span = startSpan + (endSpan - startSpan) * t;
    final Offset c0 = posAt(p0, span);
    final Offset c1 = posAt(p1, span);
    GestureBinding.instance.handlePointerEvent(
      PointerMoveEvent(
        pointer: p0,
        position: c0,
        delta: c0 - prev0,
        kind: PointerDeviceKind.touch,
      ),
    );
    GestureBinding.instance.handlePointerEvent(
      PointerMoveEvent(
        pointer: p1,
        position: c1,
        delta: c1 - prev1,
        kind: PointerDeviceKind.touch,
      ),
    );
    prev0 = c0;
    prev1 = c1;
    if (stepDuration > Duration.zero) {
      await Future<void>.delayed(stepDuration);
    }
  }
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(
      pointer: p0,
      position: prev0,
      kind: PointerDeviceKind.touch,
    ),
  );
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(
      pointer: p1,
      position: prev1,
      kind: PointerDeviceKind.touch,
    ),
  );
}

/// Validate that [args] contains [key] of the expected primitive type.
/// Returns `null` on success, or a `schema_violation` [ToolResult].
ToolResult? requireField(
  Map<String, Object?> args,
  String key,
  Type type, {
  bool optional = false,
}) {
  if (!args.containsKey(key)) {
    if (optional) return null;
    return ToolResult(
      ok: false,
      error:
          '${CoreToolErrorCode.schemaViolation}: missing required field "$key"',
    );
  }
  final Object? v = args[key];
  if (v == null) {
    return ToolResult(
      ok: false,
      error:
          '${CoreToolErrorCode.schemaViolation}: field "$key" must be $type',
    );
  }
  // Accept the declared primitive — with lenient coercion for numeric
  // fields. Some model backends (notably qwen via swift-infer) emit
  // integer/number arguments as JSON strings ("5") or as whole-valued
  // doubles (5.0). The model is *told* the field is an integer via the
  // tool `input_schema` and ignores it — it repeats the string-typed
  // call without self-correcting (the failed result is in its action
  // history, yet it does not adapt), so coercing here is more robust than
  // rejecting. We mutate `args` in place to the schema's expected numeric
  // type so downstream reads (`args[key]! as int`) succeed unchanged.
  // See lenny-cx6.50.
  if (type == num) {
    if (v is num) return null;
    final num? c = _coerceNum(v);
    if (c != null) {
      args[key] = c;
      return null;
    }
  } else if (type == int) {
    if (v is int) return null;
    final int? c = _coerceInt(v);
    if (c != null) {
      args[key] = c;
      return null;
    }
  } else if (type == double) {
    if (v is num) return null;
    final num? c = _coerceNum(v);
    if (c != null) {
      args[key] = c.toDouble();
      return null;
    }
  } else if (type == String) {
    if (v is String) return null;
  } else if (type == bool) {
    if (v is bool) return null;
  }
  return ToolResult(
    ok: false,
    error:
        '${CoreToolErrorCode.schemaViolation}: field "$key" must be $type, '
        'got ${v.runtimeType}',
  );
}

/// Coerce a JSON value to an `int` for lenient numeric validation.
///
/// Accepts an actual `int`, a whole-valued finite `double` (`5.0`), or a
/// numeric string (`"5"`, `"5.0"`). Returns `null` when the value cannot
/// losslessly represent an integer (e.g. `"5.5"`, `"abc"`). See
/// [requireField] / lenny-cx6.50.
int? _coerceInt(Object? v) {
  if (v is int) return v;
  if (v is double && v.isFinite && v == v.roundToDouble()) return v.toInt();
  if (v is String) {
    final String s = v.trim();
    final int? i = int.tryParse(s);
    if (i != null) return i;
    final double? d = double.tryParse(s);
    if (d != null && d.isFinite && d == d.roundToDouble()) return d.toInt();
  }
  return null;
}

/// Coerce a JSON value to a `num`: accepts any `num` or a numeric string.
/// Returns `null` when the string is not parseable. See [requireField].
num? _coerceNum(Object? v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v.trim());
  return null;
}

/// Build a `target_not_found` [ToolResult] for an unknown semantics id.
ToolResult targetNotFound(int id) => ToolResult(
      ok: false,
      error: '${CoreToolErrorCode.targetNotFound}: node $id',
    );
