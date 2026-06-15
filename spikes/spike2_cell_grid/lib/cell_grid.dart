/// Spike 2: pure-stdlib styled cell grid with double buffering,
/// per-frame minimal cell diff, and minimal ANSI emission.
///
/// Imports ONLY `dart:*` libraries — no packages, no Flutter engine.
library;

import 'dart:convert' show utf8;

/// One styled terminal cell: a Unicode code point plus minimal style.
class Cell {
  /// Unicode code point to render.
  final int rune;

  /// Foreground 256-color index (0..255), or -1 for terminal default.
  final int fg;

  /// Background 256-color index (0..255), or -1 for terminal default.
  final int bg;

  final bool bold;

  const Cell(this.rune, {this.fg = -1, this.bg = -1, this.bold = false});

  static const Cell blank = Cell(0x20);

  bool sameStyleAs(Cell other) =>
      fg == other.fg && bg == other.bg && bold == other.bold;

  @override
  bool operator ==(Object other) =>
      other is Cell &&
      other.rune == rune &&
      other.fg == fg &&
      other.bg == bg &&
      other.bold == bold;

  @override
  int get hashCode => Object.hash(rune, fg, bg, bold);

  @override
  String toString() =>
      "Cell('${String.fromCharCode(rune)}', fg=$fg, bg=$bg, bold=$bold)";
}

/// A single cell that differs between the back and front buffer.
class CellChange {
  final int x;
  final int y;
  final Cell cell;

  const CellChange(this.x, this.y, this.cell);

  @override
  String toString() => 'CellChange($x,$y,$cell)';
}

/// Double-buffered W x H cell grid.
///
/// Draw ops target the back buffer; [swap] diffs back vs front, promotes
/// the back buffer to front, and returns the minimal change list.
class CellGrid {
  final int width;
  final int height;
  final List<Cell> _front;
  final List<Cell> _back;

  CellGrid(this.width, this.height)
      : _front = List<Cell>.filled(width * height, Cell.blank),
        _back = List<Cell>.filled(width * height, Cell.blank);

  int get cellCount => width * height;

  Cell frontAt(int x, int y) => _front[y * width + x];
  Cell backAt(int x, int y) => _back[y * width + x];

  /// Snapshot of the current front buffer (row-major).
  List<Cell> frontSnapshot() => List<Cell>.of(_front);

  bool _inBounds(int x, int y) => x >= 0 && x < width && y >= 0 && y < height;

  /// Sets one cell in the back buffer; silently clips out-of-bounds.
  void set(int x, int y, Cell cell) {
    if (_inBounds(x, y)) _back[y * width + x] = cell;
  }

  /// Fills the entire back buffer with [fill].
  void clear([Cell fill = Cell.blank]) {
    for (var i = 0; i < _back.length; i++) {
      _back[i] = fill;
    }
  }

  /// Writes [text] starting at (x, y); clips at grid edges.
  void putText(
    int x,
    int y,
    String text, {
    int fg = -1,
    int bg = -1,
    bool bold = false,
  }) {
    var cx = x;
    for (final rune in text.runes) {
      set(cx, y, Cell(rune, fg: fg, bg: bg, bold: bold));
      cx++;
    }
  }

  /// Draws a box outline with Unicode box-drawing characters and an
  /// optional [title] embedded in the top border. When [fillInterior] is
  /// true the interior is filled with styled blanks.
  void drawBox(
    int x,
    int y,
    int w,
    int h, {
    String? title,
    int fg = -1,
    int bg = -1,
    bool bold = false,
    bool fillInterior = false,
  }) {
    if (w < 2 || h < 2) return;
    Cell c(int rune) => Cell(rune, fg: fg, bg: bg, bold: bold);
    const tl = 0x250C, tr = 0x2510, bl = 0x2514, br = 0x2518; // ┌ ┐ └ ┘
    const hbar = 0x2500, vbar = 0x2502; // ─ │
    set(x, y, c(tl));
    set(x + w - 1, y, c(tr));
    set(x, y + h - 1, c(bl));
    set(x + w - 1, y + h - 1, c(br));
    for (var i = 1; i < w - 1; i++) {
      set(x + i, y, c(hbar));
      set(x + i, y + h - 1, c(hbar));
    }
    for (var j = 1; j < h - 1; j++) {
      set(x, y + j, c(vbar));
      set(x + w - 1, y + j, c(vbar));
      if (fillInterior) {
        for (var i = 1; i < w - 1; i++) {
          set(x + i, y + j, Cell(0x20, fg: fg, bg: bg));
        }
      }
    }
    if (title != null && w > 5) {
      final maxLen = w - 5;
      final t = title.length > maxLen ? title.substring(0, maxLen) : title;
      putText(x + 2, y, ' $t ', fg: fg, bg: bg, bold: true);
    }
  }

  /// Diffs back vs front, promotes the back buffer to front, and returns
  /// the minimal change list (exactly the cells that differ).
  ///
  /// The back buffer keeps its contents, so each frame draws incrementally
  /// on top of the current scene (or calls [clear] first to redraw).
  List<CellChange> swap() {
    final changes = <CellChange>[];
    for (var i = 0; i < _back.length; i++) {
      if (_back[i] != _front[i]) {
        changes.add(CellChange(i % width, i ~/ width, _back[i]));
        _front[i] = _back[i];
      }
    }
    return changes;
  }
}

/// Encodes change lists into minimal ANSI escape sequences.
///
/// Write-only output: cursor positioning (`ESC[row;colH`, 1-based) plus
/// 256-color SGR (`ESC[0;1;38;5;N;48;5;Mm`). Adjacent changed cells on the
/// same row share one cursor move (horizontal run batching); SGR is emitted
/// only when the style actually changes between emitted cells; a single
/// `ESC[0m` reset terminates the payload. No terminal queries, no raw mode.
class AnsiEncoder {
  static const String _csi = '\x1b[';

  String encode(List<CellChange> changes) {
    if (changes.isEmpty) return '';
    final sorted = List<CellChange>.of(changes)
      ..sort((a, b) => a.y != b.y ? a.y - b.y : a.x - b.x);
    final sb = StringBuffer();
    int? fg, bg;
    bool? bold;
    var nextX = -1, nextY = -1;
    for (final ch in sorted) {
      if (ch.y != nextY || ch.x != nextX) {
        sb.write('$_csi${ch.y + 1};${ch.x + 1}H');
      }
      final c = ch.cell;
      if (c.fg != fg || c.bg != bg || c.bold != bold) {
        sb.write(_sgr(c));
        fg = c.fg;
        bg = c.bg;
        bold = c.bold;
      }
      sb.writeCharCode(c.rune);
      nextX = ch.x + 1;
      nextY = ch.y;
    }
    sb.write('${_csi}0m');
    return sb.toString();
  }

  /// UTF-8 bytes of [encode] (box-drawing runes are multi-byte).
  List<int> encodeBytes(List<CellChange> changes) =>
      utf8.encode(encode(changes));

  /// Byte cost of a naive full-screen redraw of [grid]'s front buffer,
  /// produced by the same encoder over every cell — the fair baseline that
  /// per-frame diffing is measured against.
  int fullRedrawBytes(CellGrid grid) {
    final all = <CellChange>[
      for (var y = 0; y < grid.height; y++)
        for (var x = 0; x < grid.width; x++)
          CellChange(x, y, grid.frontAt(x, y)),
    ];
    return encodeBytes(all).length;
  }

  String _sgr(Cell c) {
    final sb = StringBuffer('${_csi}0');
    if (c.bold) sb.write(';1');
    if (c.fg >= 0) sb.write(';38;5;${c.fg}');
    if (c.bg >= 0) sb.write(';48;5;${c.bg}');
    sb.write('m');
    return sb.toString();
  }
}
