/// Spike 2 driver. Two modes, both pipe-safe (write-only ANSI, no terminal
/// queries, no raw mode, no dart:ffi):
///
///   --self-test  plain assertions, PASS/FAIL lines, non-zero exit on failure
///   --demo       titled boxes + a box animated across ~10 frames, real ANSI
library;

import 'dart:io';
import 'dart:math';

import 'package:spike2_cell_grid/cell_grid.dart';

void main(List<String> args) {
  if (args.contains('--self-test')) {
    exit(_selfTest());
  }
  if (args.contains('--demo')) {
    _demo();
    return;
  }
  stderr.writeln('usage: demo.dart (--self-test | --demo)');
  exit(2);
}

// ---------------------------------------------------------------------------
// --self-test
// ---------------------------------------------------------------------------

int _failures = 0;

void _check(String name, bool ok, [String? detail]) {
  if (ok) {
    print('PASS $name');
  } else {
    _failures++;
    print('FAIL $name${detail == null ? '' : ' — $detail'}');
  }
}

int _selfTest() {
  _testDiffCorrectnessAndMinimality();
  _testIdempotence();
  _testEmissionEconomy();
  if (_failures == 0) {
    print('SPIKE2: self-test OK — all checks passed');
    return 0;
  }
  print('SPIKE2: self-test FAILED — $_failures check(s) failed');
  return 1;
}

/// (a) diff correctness: applying the emitted change list to a copy of the
/// old front buffer must reproduce the back buffer exactly, over several
/// randomized mutation rounds (constant RNG seed for reproducibility).
/// (b) diff minimality: change count == number of cells that actually differ.
void _testDiffCorrectnessAndMinimality() {
  const seed = 42;
  const rounds = 8;
  final rng = Random(seed);
  final grid = CellGrid(40, 12);
  grid.drawBox(0, 0, 40, 12, title: 'spike2', fg: 6);
  grid.swap(); // establish a non-trivial frame 0

  var allCorrect = true;
  var allMinimal = true;
  String? detail;
  for (var round = 0; round < rounds; round++) {
    final before = grid.frontSnapshot();
    _randomMutations(grid, rng, round);

    // Count truly differing cells BEFORE swap (ground truth for minimality).
    var expected = 0;
    for (var y = 0; y < grid.height; y++) {
      for (var x = 0; x < grid.width; x++) {
        if (grid.backAt(x, y) != grid.frontAt(x, y)) expected++;
      }
    }

    final changes = grid.swap();
    if (changes.length != expected) {
      allMinimal = false;
      detail = 'round $round: ${changes.length} changes vs $expected differing';
    }

    // Replay the change list onto the old front; must equal the new front
    // (== the back buffer that was just promoted).
    final replay = List<Cell>.of(before);
    for (final ch in changes) {
      replay[ch.y * grid.width + ch.x] = ch.cell;
    }
    final after = grid.frontSnapshot();
    for (var i = 0; i < replay.length; i++) {
      if (replay[i] != after[i]) {
        allCorrect = false;
        detail = 'round $round: replay mismatch at index $i';
        break;
      }
    }
  }
  _check('diff-correctness ($rounds randomized rounds, seed $seed)',
      allCorrect, detail);
  _check('diff-minimality (change count == differing cells, $rounds rounds)',
      allMinimal, detail);
}

void _randomMutations(CellGrid g, Random rng, int round) {
  final nOps = 3 + rng.nextInt(6);
  for (var i = 0; i < nOps; i++) {
    switch (rng.nextInt(4)) {
      case 0: // single styled cell
        g.set(
          rng.nextInt(g.width),
          rng.nextInt(g.height),
          Cell(0x41 + rng.nextInt(26),
              fg: rng.nextInt(16),
              bg: rng.nextBool() ? rng.nextInt(16) : -1,
              bold: rng.nextBool()),
        );
      case 1: // text run (may clip at right edge)
        g.putText(rng.nextInt(g.width), rng.nextInt(g.height), 'r$round-op$i',
            fg: rng.nextInt(256), bold: rng.nextBool());
      case 2: // box (may clip)
        g.drawBox(rng.nextInt(g.width - 6), rng.nextInt(g.height - 3),
            6 + rng.nextInt(10), 3 + rng.nextInt(4),
            title: 'b$i', fg: rng.nextInt(16));
      case 3: // no-op rewrite: must NOT show up in the diff
        final x = rng.nextInt(g.width), y = rng.nextInt(g.height);
        g.set(x, y, g.backAt(x, y));
    }
  }
}

/// (c) idempotence: swap with no draws -> 0 changes.
void _testIdempotence() {
  final grid = CellGrid(20, 6);
  grid.drawBox(1, 1, 18, 4, title: 'idem', fg: 2);
  grid.swap();
  final changes = grid.swap();
  _check('idempotence (swap with no draws -> 0 changes)', changes.isEmpty,
      'got ${changes.length} changes');
}

/// (d) emission economy: for a frame where k of N cells changed, diff bytes
/// must beat a naive full-screen redraw for small k. Reports per-frame stats.
void _testEmissionEconomy() {
  final enc = AnsiEncoder();
  final grid = CellGrid(80, 25); // N = 2000
  final n = grid.cellCount;

  // Frame 1: initial scene (large k — diffing buys nothing here, by design).
  grid.drawBox(2, 1, 30, 8, title: 'alpha', fg: 6);
  grid.drawBox(40, 3, 24, 10, title: 'beta', fg: 3);
  grid.putText(4, 20, 'status: nominal', fg: 2, bold: true);
  var changes = grid.swap();
  _report(1, changes.length, n, enc.encodeBytes(changes).length,
      enc.fullRedrawBytes(grid));

  // Frames 2..4: small mutations — diff must beat the full redraw.
  var economical = true;
  var sane = true;
  for (var frame = 2; frame <= 4; frame++) {
    grid.putText(4, 20, 'status: frame $frame', fg: 5, bold: frame.isEven);
    grid.set(60 + frame, 22, const Cell(0x2588, fg: 1)); // progress block █
    changes = grid.swap();
    final emitted = enc.encodeBytes(changes).length;
    final full = enc.fullRedrawBytes(grid);
    _report(frame, changes.length, n, emitted, full);
    if (emitted >= full) economical = false;
    if (changes.length > 32) sane = false; // k must actually be small
  }
  _check('emission-economy (diff bytes < full-redraw bytes for small k)',
      economical && sane);
}

void _report(int frame, int k, int n, int emitted, int full) {
  print('SPIKE2: frame $frame: changed $k/$n cells, '
      'emitted $emitted bytes vs $full full-redraw');
}

// ---------------------------------------------------------------------------
// --demo
// ---------------------------------------------------------------------------

void _demo() {
  final grid = CellGrid(80, 24);
  final enc = AnsiEncoder();
  stdout.write('\x1b[2J\x1b[H'); // clear + home; write-only, pipe-safe
  const frames = 10;
  for (var frame = 0; frame < frames; frame++) {
    grid.clear();
    grid.drawBox(1, 1, 34, 9, title: 'lenny', fg: 6);
    grid.putText(3, 3, 'pure-Dart TUI render surface', fg: 7);
    grid.putText(3, 5, 'frame ${frame + 1}/$frames', fg: 2, bold: true);
    grid.drawBox(44, 1, 30, 9, title: 'stats', fg: 3);
    grid.putText(46, 3, 'double-buffered cell diff', fg: 3);
    grid.drawBox(4 + frame * 4, 13, 16, 6, title: 'mover', fg: 5, bold: true);
    final changes = grid.swap();
    final bytes = enc.encodeBytes(changes);
    stdout.add(bytes);
    stderr.writeln(
        'demo frame ${frame + 1}: ${changes.length} changes, ${bytes.length} bytes');
    sleep(const Duration(milliseconds: 40));
  }
  stdout.write('\x1b[24;1H\x1b[0m\n'); // park cursor below the scene, reset
}
