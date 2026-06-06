import 'package:flutter/widgets.dart';

/// Walk the live element tree and find the [EditableTextState] whose render
/// object's global bounding rect has the largest intersection with
/// [targetGlobalRect].
///
/// Returns null when the tree is unavailable or no [EditableText] element
/// intersects the target rect.
EditableTextState? resolveEditableText(Rect targetGlobalRect) {
  final Element? root = WidgetsBinding.instance.rootElement;
  if (root == null) return null;

  EditableTextState? best;
  double bestArea = 0;

  void visit(Element el) {
    if (el is StatefulElement && el.state is EditableTextState) {
      final RenderObject? ro = el.renderObject;
      if (ro is RenderBox && ro.attached) {
        final Rect global = ro.localToGlobal(Offset.zero) & ro.size;
        final Rect intersection = global.intersect(targetGlobalRect);
        if (!intersection.isEmpty) {
          final double area = intersection.width * intersection.height;
          if (area > bestArea) {
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
