/// Spike 4: the live wiring — owner dirty set -> microtask-scheduled flush ->
/// targeted repaint -> double-buffered diff -> minimal ANSI.
///
/// `PerceptionOwner.mountRoot(tree)`; `owner.onNeedsHarvest` schedules (via
/// [scheduleMicrotask]) one pass: `flushHarvest()` -> repaint ONLY the boxes
/// whose content rebuilt, into the back buffer -> `swap()` -> collect
/// [CellChange]s -> encode ANSI. Every pass is recorded as a [FrameRecord]
/// (the test hook: change list + bytes emitted, per frame).
library;

import 'dart:async';

import 'package:perception/perception.dart';
import 'package:spike2_cell_grid/cell_grid.dart';

import 'renderer.dart';

/// Screen-region dirty marks. The builder of a watched box calls [mark] when
/// it rebuilds — the spike's stand-in for a render object marking its own
/// region dirty. The static box never marks, so it is never repainted.
class RepaintNotifier {
  final Set<int> _dirty = {};

  void mark(int boxIndex) => _dirty.add(boxIndex);

  Set<int> drain() {
    final out = Set<int>.of(_dirty);
    _dirty.clear();
    return out;
  }
}

/// Everything recorded about one emit pass (initial paint or flush pass).
class FrameRecord {
  /// 0 = initial full frame; 1.. = update frames.
  final int index;

  /// Indices of the top-level boxes repainted into the back buffer.
  final Set<int> repaintedBoxes;

  /// Minimal cell diff from [CellGrid.swap].
  final List<CellChange> changes;

  /// UTF-8 ANSI bytes emitted for this frame (empty when nothing changed).
  final List<int> bytes;

  const FrameRecord(this.index, this.repaintedBoxes, this.changes, this.bytes);
}

/// Owns the mounted tree, the grid, and the event->paint pipeline.
class LiveLoop {
  LiveLoop({
    required Perception root,
    required this.notifier,
    int width = 40,
    int boxHeight = 4,
    this.onFrame,
  }) : renderer = TreeRenderer(width: width, boxHeight: boxHeight) {
    rootElement = owner.mountRoot(root) as NodeElement;
    grid = CellGrid(width, rootElement.children.length * boxHeight);
    boxRects = renderer.layout(rootElement);
    owner.onNeedsHarvest = _scheduleFlush;
  }

  final PerceptionOwner owner = PerceptionOwner();
  final RepaintNotifier notifier;
  final TreeRenderer renderer;
  final AnsiEncoder encoder = AnsiEncoder();
  final void Function(FrameRecord frame)? onFrame;

  late final NodeElement rootElement;
  late final CellGrid grid;
  late final List<Rect> boxRects;

  /// Test hook: per-frame change list + bytes emitted.
  final List<FrameRecord> frames = [];

  /// Number of flushHarvest passes run (excludes the initial frame).
  int flushCount = 0;

  bool _passScheduled = false;
  bool _started = false;

  /// Paints + emits the initial full frame (frame 0).
  void start() {
    assert(!_started, 'start() called twice');
    _started = true;
    // The initial mount already ran every builder once; frame 0 paints the
    // whole scene regardless, so discard those marks.
    notifier.drain();
    renderer.paintAll(grid, rootElement);
    _emit(repainted: {for (var i = 0; i < boxRects.length; i++) i});
  }

  void _scheduleFlush() {
    if (_passScheduled) return;
    _passScheduled = true;
    scheduleMicrotask(_flushPass);
  }

  void _flushPass() {
    _passScheduled = false;
    owner.flushHarvest();
    flushCount++;
    final repainted = notifier.drain();
    for (final i in repainted) {
      renderer.paintBox(grid, rootElement.children[i], boxRects[i]);
    }
    _emit(repainted: repainted);
  }

  void _emit({required Set<int> repainted}) {
    final changes = grid.swap();
    final bytes = encoder.encodeBytes(changes);
    final frame = FrameRecord(frames.length, repainted, changes, bytes);
    frames.add(frame);
    onFrame?.call(frame);
  }

  void dispose() {
    owner.dispose();
  }
}
