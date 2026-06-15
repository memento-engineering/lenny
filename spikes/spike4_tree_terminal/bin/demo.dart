/// Spike 4 demo: ~10 scripted events through the live loop, emitting real
/// ANSI to stdout (pipe-safe, write-only, deterministic content) and
/// per-frame stats lines prefixed "SPIKE4:" to stderr.
///
/// Run on a real terminal to watch the boxes update in place:
///   dart run bin/demo.dart --demo
library;

import 'dart:async';
import 'dart:io';

import 'package:spike2_cell_grid/cell_grid.dart';
import 'package:spike4_tree_terminal/fixture.dart';
import 'package:spike4_tree_terminal/live_loop.dart';

Future<void> main(List<String> args) async {
  if (!args.contains('--demo')) {
    stdout.writeln('usage: dart run bin/demo.dart --demo');
    return;
  }

  final fx = Spike4Fixture();
  var totalBytes = 0;
  final loop = LiveLoop(
    root: fx.root,
    notifier: fx.notifier,
    onFrame: (f) {
      stdout.add(f.bytes);
      totalBytes += f.bytes.length;
      final boxes = f.repaintedBoxes.toList()..sort();
      stderr.writeln('SPIKE4: frame=${f.index} repainted=$boxes '
          'changedCells=${f.changes.length} ansiBytes=${f.bytes.length}');
    },
  );

  // Write-only setup: clear screen + home. No terminal queries, no raw mode.
  stdout.write('\x1b[2J\x1b[H');
  loop.start(); // frame 0: full scene

  Future<void> step(void Function() fire) async {
    fire();
    // Sleep only — lets the event + flush microtasks run, and animates the
    // scene when watched on a live terminal. Content is fully scripted.
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }

  await step(() => fx.ticker.add(1)); //  1
  await step(() => fx.feed.add('booting')); //  2
  await step(() => fx.ticker.add(2)); //  3
  await step(() => fx.ticker.add(3)); //  4
  await step(() => fx.feed.add('render loop live')); //  5
  await step(() => fx.ticker.add(3)); //  6  duplicate -> zero-cell frame
  await step(() => fx.ticker.add(42)); //  7
  await step(() => fx.feed.add('diffing only')); //  8
  await step(() => fx.ticker.add(137)); //  9
  await step(() => fx.feed.add('done')); // 10

  // Park the cursor below the scene and reset style.
  stdout.write('\x1b[${loop.grid.height + 1};1H\x1b[0m');
  await stdout.flush();

  final updateFrames = loop.frames.skip(1).toList();
  final updateBytes =
      updateFrames.fold<int>(0, (sum, f) => sum + f.bytes.length);
  final fullRedraw = AnsiEncoder().fullRedrawBytes(loop.grid);
  stderr.writeln('SPIKE4: summary frames=${loop.frames.length} '
      'totalAnsiBytes=$totalBytes updateFrames=${updateFrames.length} '
      'updateAnsiBytes=$updateBytes fullRedrawBytesPerFrame=$fullRedraw');

  loop.dispose();
  await fx.dispose();
}
