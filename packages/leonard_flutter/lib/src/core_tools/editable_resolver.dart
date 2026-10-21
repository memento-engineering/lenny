import 'package:flutter/widgets.dart';

/// Walk the live element tree and find the [EditableTextState] whose render
/// object's global bounding rect has the largest intersection with
/// [targetGlobalRect].
///
/// Returns null when the tree is unavailable or no [EditableText] element
/// intersects the target rect.
///
/// Only an [EditableText] that is on stage is a candidate. The walk goes
/// through [Element.debugVisitOnstageChildren] (an ordinary method, live in
/// release builds despite its name, and the walk flutter_test's skipOffstage
/// uses), so it never enters the Overlay's entries under an opaque route, an
/// [IndexedStack]'s unselected children, [Offstage] content, or slivers that
/// are not visible. Those subtrees keep geometry that is stale (laid out
/// before they were hidden) or absent, and a field in them is not on screen
/// to be typed into. A field whose render box has no size is skipped too:
/// reading its geometry throws.
///
/// Among candidates whose intersections tie, the last one visited wins. Of
/// two overlapping on-stage siblings, as in a [Stack] or a non-opaque route
/// over the route beneath it, the later one paints on top.
EditableTextState? resolveEditableText(Rect targetGlobalRect) {
  final Element? root = WidgetsBinding.instance.rootElement;
  if (root == null) return null;

  EditableTextState? best;
  double bestArea = 0;

  void visit(Element el) {
    if (el is StatefulElement && el.state is EditableTextState) {
      final RenderObject? ro = el.renderObject;
      if (ro is RenderBox && ro.attached && ro.hasSize) {
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
    el.debugVisitOnstageChildren(visit);
  }

  root.debugVisitOnstageChildren(visit);
  return best;
}
