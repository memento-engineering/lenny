/// Spike 4: tree -> terminal end-to-end via the Watch dirty set.
///
/// Proves the A4 update path: stream event -> perceived() -> owner dirty set
/// -> onNeedsHarvest -> microtask flushHarvest -> targeted repaint ->
/// double-buffered diff -> minimal ANSI, with repaint LOCALITY (changed cells
/// confined to the changed box's rect; the static box untouched, unrebuilt).
library;

import 'package:spike2_cell_grid/cell_grid.dart';
import 'package:spike4_tree_terminal/fixture.dart';
import 'package:spike4_tree_terminal/live_loop.dart';
import 'package:spike4_tree_terminal/renderer.dart';
import 'package:test/test.dart';

import 'snapshots.dart';

void main() {
  late Spike4Fixture fx;
  late LiveLoop loop;

  setUp(() {
    fx = Spike4Fixture();
    loop = LiveLoop(root: fx.root, notifier: fx.notifier);
    loop.start();
  });

  tearDown(() async {
    loop.dispose();
    await fx.dispose();
  });

  test('(a) initial frame paints the full scene', () {
    expect(loop.frames, hasLength(1));
    expect(loop.flushCount, 0, reason: 'frame 0 is a paint, not a flush');
    final f0 = loop.frames[0];
    expect(f0.repaintedBoxes, {0, 1, 2});
    expect(f0.changes, isNotEmpty);
    expect(f0.bytes, isNotEmpty);
    expect(renderFront(loop.grid), initialSnapshot);
  });

  test(
      '(b) one stream event -> exactly one flush pass; '
      'changed cells confined to the watched box rect (LOCALITY)', () async {
    fx.ticker.add(7);
    await pumpEventQueue();

    expect(loop.flushCount, 1, reason: 'one event must cost one flush pass');
    expect(loop.frames, hasLength(2));
    final f = loop.frames[1];
    expect(f.repaintedBoxes, {0}, reason: 'only the ticker box repaints');
    expect(f.changes, isNotEmpty);

    final tickerRect = loop.boxRects[0];
    final staticRect = loop.boxRects[1];
    final feedRect = loop.boxRects[2];
    for (final c in f.changes) {
      expect(tickerRect.contains(c.x, c.y), isTrue,
          reason: '$c escaped the watched box rect $tickerRect');
    }
    expect(f.changes.where((c) => staticRect.contains(c.x, c.y)), isEmpty,
        reason: 'zero cells may change inside the static box rect');
    expect(f.changes.where((c) => feedRect.contains(c.x, c.y)), isEmpty,
        reason: 'zero cells may change inside the other live box rect');

    // Economy: the diff frame must be far cheaper than a full redraw.
    final fullRedraw = AnsiEncoder().fullRedrawBytes(loop.grid);
    expect(f.bytes.length, lessThan(fullRedraw ~/ 10),
        reason: 'diff bytes ${f.bytes.length} vs full redraw $fullRedraw');
  });

  test('(c) event rendering identically -> zero changed cells (dedup)',
      () async {
    fx.ticker.add(7);
    await pumpEventQueue();
    final framesBefore = loop.frames.length;
    final buildsBefore = fx.tickerBuilds;

    fx.ticker.add(7); // same value: rebuild happens, pixels identical
    await pumpEventQueue();

    expect(fx.tickerBuilds, buildsBefore + 1,
        reason: 'the Watch DID rebuild on the duplicate event');
    expect(loop.frames, hasLength(framesBefore + 1),
        reason: 'a flush pass DID run');
    final f = loop.frames.last;
    expect(f.repaintedBoxes, {0},
        reason: 'the box WAS repainted into the back buffer');
    expect(f.changes, isEmpty,
        reason: 'double-buffer diff dedups the identical repaint');
    expect(f.bytes, isEmpty, reason: 'zero changed cells -> zero ANSI bytes');
  });

  test(
      '(d) K successive distinct events -> expected final state; '
      'per-frame diffs small relative to grid size', () async {
    final tickerValues = [1, 2, 3, 42, 137];
    final changedPerFrame = <int>[];
    final bytesPerFrame = <int>[];
    for (final v in tickerValues) {
      fx.ticker.add(v);
      await pumpEventQueue();
      changedPerFrame.add(loop.frames.last.changes.length);
      bytesPerFrame.add(loop.frames.last.bytes.length);
    }
    fx.feed.add('done');
    await pumpEventQueue();
    changedPerFrame.add(loop.frames.last.changes.length);
    bytesPerFrame.add(loop.frames.last.bytes.length);

    expect(loop.flushCount, 6);
    expect(renderFront(loop.grid), finalSnapshot);

    final cellCount = loop.grid.cellCount;
    final fullRedraw = AnsiEncoder().fullRedrawBytes(loop.grid);
    // The per-frame economy record (also asserted below):
    // ignore: avoid_print
    print('SPIKE4(d): grid=${loop.grid.width}x${loop.grid.height} '
        '($cellCount cells); per-frame changed cells=$changedPerFrame; '
        'per-frame ANSI bytes=$bytesPerFrame; fullRedrawBytes=$fullRedraw');
    for (final n in changedPerFrame) {
      expect(n, greaterThan(0), reason: 'every distinct event changes cells');
      expect(n, lessThan(cellCount ~/ 10),
          reason: 'per-frame diff must stay under 10% of the grid '
              '(got $n of $cellCount)');
    }
  });

  test('(e) the static box element is never rebuilt', () async {
    final staticElementBefore = loop.rootElement.children[1];
    expect(fx.staticBuilds, 1, reason: 'built exactly once, at mount');
    expect(fx.tickerBuilds, 1);
    expect(fx.feedBuilds, 1);

    fx.ticker.add(1);
    await pumpEventQueue();
    fx.ticker.add(2);
    await pumpEventQueue();
    fx.feed.add('hi');
    await pumpEventQueue();

    expect(fx.staticBuilds, 1,
        reason: 'no stream event may rebuild the static box');
    expect(fx.tickerBuilds, 3, reason: 'mount + 2 ticker events');
    expect(fx.feedBuilds, 2, reason: 'mount + 1 feed event');
    expect(identical(loop.rootElement.children[1], staticElementBefore), isTrue,
        reason: 'same element instance across all events');
  });
}
