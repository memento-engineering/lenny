import 'package:flutter/widgets.dart';

/// Walk the live element tree and find the [EditableTextState] whose render
/// object's global bounding rect has the largest intersection with
/// [targetGlobalRect].
///
/// Returns null when the tree is unavailable or no [EditableText] element
/// intersects the target rect.
///
/// An [EditableText] whose render box has never been laid out is skipped. The
/// Overlay keeps covered routes attached without laying them out, so a page
/// stack built with a text-field route already covered holds sizeless boxes;
/// reading their geometry throws, and they are not on screen to be typed into.
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
