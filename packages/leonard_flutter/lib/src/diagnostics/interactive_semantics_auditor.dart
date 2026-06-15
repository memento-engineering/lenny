import 'package:flutter/material.dart';

import 'interactive_semantics_warning.dart';

/// Walks the live widget tree and emits a warning for each candidate
/// interactable widget whose ancestor chain lacks a label-bearing
/// `Semantics` annotation. Connect-time diagnostic; not invoked per turn.
///
/// The walker recognises:
/// - `GestureDetector` with a non-null tap / long-press / double-tap
///   callback;
/// - `InkResponse` (and therefore `InkWell`) with a non-null tap /
///   long-press / double-tap callback;
/// - any widget whose runtime type name appears in
///   [extraInteractiveTypes].
class InteractiveSemanticsAuditor {
  InteractiveSemanticsAuditor({this.extraInteractiveTypes = const <String>[]});

  /// Additional class names treated as interactable, e.g. user-defined
  /// custom button widgets. Compared against `widget.runtimeType.toString()`.
  final List<String> extraInteractiveTypes;

  List<InteractiveSemanticsWarning> audit(Element root) {
    final List<InteractiveSemanticsWarning> out = <InteractiveSemanticsWarning>[];
    void visit(Element el) {
      final Widget w = el.widget;
      final String type = w.runtimeType.toString();
      if (_isInteractive(w, type) && !_hasAncestorSemantics(el)) {
        out.add(InteractiveSemanticsWarning(
          widgetType: type,
          location: _locationOf(el),
          suggestedFixPointer: kExtensionGuideFixPointer,
        ));
      }
      el.visitChildren(visit);
    }

    root.visitChildren(visit);
    return out;
  }

  bool _isInteractive(Widget w, String type) {
    if (w is GestureDetector) {
      return w.onTap != null ||
          w.onLongPress != null ||
          w.onDoubleTap != null;
    }
    if (w is InkResponse) {
      // InkWell extends InkResponse, so this catches both.
      return w.onTap != null ||
          w.onLongPress != null ||
          w.onDoubleTap != null;
    }
    return extraInteractiveTypes.contains(type);
  }

  bool _hasAncestorSemantics(Element el) {
    bool found = false;
    el.visitAncestorElements((Element a) {
      final Widget aw = a.widget;
      if (aw is Semantics) {
        if (aw.properties.label != null || aw.properties.button == true) {
          found = true;
          return false;
        }
      }
      return true;
    });
    return found;
  }

  String _locationOf(Element el) {
    try {
      return el.debugGetCreatorChain(1);
    } catch (_) {
      return el.widget.runtimeType.toString();
    }
  }
}
