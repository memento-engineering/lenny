import 'package:flutter/widgets.dart';

/// Walk the live element tree and find the [EditableTextState] whose render
/// object's global bounding rect has the largest intersection with
/// [targetGlobalRect].
///
/// Returns null when the tree is unavailable or no [EditableText] element
/// intersects the target rect.
///
/// Only an [EditableText] that is on stage is a candidate. The Overlay keeps
/// the entries under an opaque route attached but off stage, and builds them
/// with tickers disabled; their geometry is stale (laid out before they were
/// covered) or absent (never laid out, where reading it throws). A field in a
/// subtree with tickers disabled, or whose render box has no size, is skipped.
///
/// Among candidates whose intersections tie, the last one visited wins: it is
/// later in paint order, so it is the one on top, as with a field on a
/// non-opaque route over a field on the route beneath it.
EditableTextState? resolveEditableText(Rect targetGlobalRect) {
  final Element? root = WidgetsBinding.instance.rootElement;
  if (root == null) return null;

  EditableTextState? best;
  double bestArea = 0;

  void visit(Element el) {
    if (el is StatefulElement && el.state is EditableTextState) {
      final RenderObject? ro = el.renderObject;
      if (ro is RenderBox &&
          ro.attached &&
          ro.hasSize &&
          TickerMode.getValuesNotifier(el).value.enabled) {
        final Rect global = ro.localToGlobal(Offset.zero) & ro.size;
        final Rect intersection = global.intersect(targetGlobalRect);
        if (!intersection.isEmpty) {
          final double area = intersection.width * intersection.height;
          if (area >= bestArea) {
            bestArea = area;
            best = el.state as EditableTextState;
          }
        }
      }
    }
    el.visitChildren(visit);
  }

  root.visitChildren(visit);
  return best;
}
