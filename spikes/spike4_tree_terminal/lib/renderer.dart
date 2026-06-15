/// Spike 4: minimal tree -> cells projection.
///
/// Walks a mounted perception element tree and paints it onto spike 2's
/// double-buffered [CellGrid]. Layout is deliberately FIXED (this spike is
/// about the update path, not layout): each child of the root [Node] is a
/// titled box of [TreeRenderer.boxHeight] rows, full grid width, stacked top
/// to bottom. Each top-level box's [Rect] is tracked so repaint locality is
/// checkable.
library;

import 'package:perception/perception.dart';
import 'package:spike2_cell_grid/cell_grid.dart';
// Spike-local leaf vocabulary lives in spike 3 (there is intentionally no
// Field in package:perception).
// ignore: implementation_imports
import 'package:spike3_schema_roundtrip/src/field.dart';

export 'package:spike3_schema_roundtrip/src/field.dart' show Field;

/// Integer screen rectangle (cell coordinates, origin top-left).
class Rect {
  final int x, y, w, h;
  const Rect(this.x, this.y, this.w, this.h);

  bool contains(int cx, int cy) =>
      cx >= x && cx < x + w && cy >= y && cy < y + h;

  @override
  String toString() => 'Rect(x=$x,y=$y,${w}x$h)';
}

/// Fixed-layout projection from a mounted tree to cells.
class TreeRenderer {
  final int width;
  final int boxHeight;
  const TreeRenderer({required this.width, this.boxHeight = 4});

  Rect rectForBox(int index) => Rect(0, index * boxHeight, width, boxHeight);

  /// One fixed rect per child of the root node, stacked top to bottom.
  List<Rect> layout(NodeElement root) =>
      [for (var i = 0; i < root.children.length; i++) rectForBox(i)];

  /// Unwraps component elements (Watch / StatefulPerception /
  /// StatelessPerception wrappers) down to the presentational [NodeElement]
  /// that carries the box title and content.
  NodeElement? resolveBoxNode(PerceptionElement el) {
    PerceptionElement? cur = el;
    while (cur is ComponentElement) {
      cur = cur.child;
    }
    return cur is NodeElement ? cur : null;
  }

  /// Field leaves under [node], depth-first, as `name: value` lines.
  List<String> contentLines(NodeElement node) {
    final lines = <String>[];
    void visit(PerceptionElement el) {
      final p = el.perception;
      if (p is Field) {
        lines.add('${p.name}: ${p.value}');
        return;
      }
      if (el is ComponentElement) {
        final c = el.child;
        if (c != null) visit(c);
        return;
      }
      if (el is NodeElement) {
        for (final c in el.children) {
          visit(c);
        }
      }
    }

    for (final c in node.children) {
      visit(c);
    }
    return lines;
  }

  /// Repaints exactly one box into the back buffer: blank-fills its rect,
  /// draws the titled border, then writes the content lines. Touches NO cell
  /// outside [rect] (CellGrid clips, and all writes are rect-relative).
  void paintBox(CellGrid grid, PerceptionElement boxElement, Rect rect) {
    for (var yy = rect.y; yy < rect.y + rect.h; yy++) {
      for (var xx = rect.x; xx < rect.x + rect.w; xx++) {
        grid.set(xx, yy, Cell.blank);
      }
    }
    final node = resolveBoxNode(boxElement);
    if (node == null) {
      grid.putText(rect.x, rect.y, '<unrenderable>');
      return;
    }
    final config = node.perception as Node;
    grid.drawBox(rect.x, rect.y, rect.w, rect.h, title: config.name);
    final lines = contentLines(node);
    final maxLen = rect.w - 4;
    for (var j = 0; j < lines.length && j < rect.h - 2; j++) {
      var line = lines[j];
      if (line.length > maxLen) line = line.substring(0, maxLen);
      grid.putText(rect.x + 2, rect.y + 1 + j, line);
    }
  }

  /// Full-scene paint (initial frame): every top-level box.
  void paintAll(CellGrid grid, NodeElement root) {
    for (var i = 0; i < root.children.length; i++) {
      paintBox(grid, root.children[i], rectForBox(i));
    }
  }
}

/// Renders the FRONT buffer to a multi-line string (trailing spaces trimmed
/// per row) — the snapshot format used by the tests.
String renderFront(CellGrid grid) {
  final rows = <String>[];
  for (var y = 0; y < grid.height; y++) {
    final sb = StringBuffer();
    for (var x = 0; x < grid.width; x++) {
      sb.writeCharCode(grid.frontAt(x, y).rune);
    }
    rows.add(sb.toString().replaceFirst(RegExp(r' +$'), ''));
  }
  return rows.join('\n');
}
