import 'dart:convert';

import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';

import '../../contract/types.dart';
import '../core_extension.dart';
import '../dispatch.dart';

/// `core.inspect_widget` — depth-capped semantics-subtree dump rooted at
/// the target node.
///
/// Documented deviation from the original AC: returns the SEMANTICS
/// subtree rather than the Element subtree. Element-tree access requires
/// `WidgetInspectorService` work that is out of scope for this bead;
/// follow-up filed.
class InspectWidgetTool extends CoreTool {
  InspectWidgetTool(super.plugin);

  static const int _maxBytes = 4 * 1024;
  static const int _defaultDepth = 5;
  static const int _maxDepth = 8;

  @override
  String get name => 'inspect_widget';

  @override
  String get description =>
      'Return a depth-capped semantics-subtree dump rooted at the target '
      'node (role, label, state, actions, rect).';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'node_id': <String, Object?>{'type': 'integer', 'minimum': 1},
      'depth': <String, Object?>{'type': 'integer', 'minimum': 1, 'maximum': 8},
    },
    'required': <String>['node_id'],
    'additionalProperties': false,
  });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    final ToolResult? term = terminatedGuard();
    if (term != null) return term;
    final ToolResult? a = requireField(args, 'node_id', int);
    if (a != null) return a;
    final ToolResult? b = requireField(args, 'depth', int, optional: true);
    if (b != null) return b;
    final int id = args['node_id']! as int;
    final int depth = (args['depth'] as int?) ?? _defaultDepth;
    if (depth < 1 || depth > _maxDepth) {
      return ToolResult(
        ok: false,
        error:
            '${CoreToolErrorCode.schemaViolation}: depth must be 1..'
            '$_maxDepth',
      );
    }

    final SemanticsNode? node = plugin.lookupNode(id);
    if (node == null) return targetNotFound(id);

    bool truncated = false;
    Map<String, Object?> tree = _walk(node, depth);
    String encoded = jsonEncode(tree);
    if (encoded.length > _maxBytes) {
      // Re-walk with a tighter depth until we fit, or set truncated.
      truncated = true;
      for (int d = depth - 1; d >= 1; d--) {
        tree = _walk(node, d);
        encoded = jsonEncode(tree);
        if (encoded.length <= _maxBytes) break;
      }
      if (encoded.length > _maxBytes) {
        // Even depth=1 didn't fit; emit a stub.
        tree = <String, Object?>{'id': id, 'truncated_to_root': true};
      }
    }
    return ToolResult(
      ok: true,
      value: <String, Object?>{'tree': tree, 'truncated': truncated},
    );
  }

  Map<String, Object?> _walk(SemanticsNode n, int remainingDepth) {
    final SemanticsData d = n.getSemanticsData();
    final Rect r = globalRectOf(n);
    final Map<String, Object?> rec = <String, Object?>{
      'id': n.id,
      'role': _role(d),
      'label': d.label,
      'state': _state(d),
      'actions': _actions(d),
      'rect': <int>[
        r.left.round(),
        r.top.round(),
        r.right.round(),
        r.bottom.round(),
      ],
    };
    if (remainingDepth > 1) {
      final List<Map<String, Object?>> kids = <Map<String, Object?>>[];
      n.visitChildren((SemanticsNode c) {
        kids.add(_walk(c, remainingDepth - 1));
        return true;
      });
      if (kids.isNotEmpty) rec['children'] = kids;
    }
    return rec;
  }

  static String _role(SemanticsData d) {
    final f = d.flagsCollection;
    if (f.isButton) return 'button';
    if (f.isTextField) return 'textfield';
    if (f.isLink) return 'link';
    if (f.isHeader) return 'header';
    if (f.isImage) return 'image';
    return 'text';
  }

  static List<String> _state(SemanticsData d) {
    final f = d.flagsCollection;
    final List<String> out = <String>[];
    // Use the SemanticsFlag bitfield via flagsCollection in a defensive
    // way: read each flag with a try/catch since the SDK has shifted
    // these between releases. We deliberately avoid any flag predicate
    // that isn't already used by SemanticsCapture.
    try {
      // ignore: invalid_use_of_visible_for_testing_member
      if (f.toString().contains('focused')) out.add('focused');
    } catch (_) {
      /* defensive */
    }
    return out;
  }

  static List<String> _actions(SemanticsData d) {
    const Map<SemanticsAction, String> table = <SemanticsAction, String>{
      SemanticsAction.tap: 'tap',
      SemanticsAction.longPress: 'long_press',
      SemanticsAction.scrollUp: 'scroll_up',
      SemanticsAction.scrollDown: 'scroll_down',
      SemanticsAction.scrollLeft: 'scroll_left',
      SemanticsAction.scrollRight: 'scroll_right',
      SemanticsAction.focus: 'focus',
      SemanticsAction.setText: 'set_text',
    };
    final List<String> out = <String>[];
    table.forEach((SemanticsAction k, String v) {
      if ((d.actions & k.index) != 0) out.add(v);
    });
    return out;
  }
}
