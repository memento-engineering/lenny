import 'package:flutter_test/flutter_test.dart';

import 'package:exploration_flutter/src/errors/error_ring_buffer.dart';

void main() {
  group('ErrorRingBuffer', () {
    late Stopwatch sw;

    setUp(() {
      sw = Stopwatch()..start();
    });

    test('asserts capacity > 0', () {
      expect(() => ErrorRingBuffer(capacity: 0, sessionClock: sw),
          throwsA(isA<AssertionError>()));
    });

    test('adds entries with monotonic seq starting at 1', () {
      final ErrorRingBuffer buf =
          ErrorRingBuffer(capacity: 10, sessionClock: sw);
      final ErrorEntry a = buf.add('a', StackTrace.current);
      final ErrorEntry b = buf.add('b', StackTrace.current);
      final ErrorEntry c = buf.add('c', StackTrace.current);
      expect(<int>[a.seq, b.seq, c.seq], <int>[1, 2, 3]);
      expect(buf.highestSeq, 3);
    });

    test('evicts oldest entry when capacity is exceeded', () {
      final ErrorRingBuffer buf =
          ErrorRingBuffer(capacity: 3, sessionClock: sw);
      buf.add('a', null);
      buf.add('b', null);
      buf.add('c', null);
      buf.add('d', null); // capacity+1 — evicts 'a'
      expect(buf.entries.map((ErrorEntry e) => e.message).toList(),
          <String>['b', 'c', 'd']);
      expect(buf.entries.map((ErrorEntry e) => e.seq).toList(),
          <int>[2, 3, 4]);
      expect(buf.highestSeq, 4,
          reason: 'eviction does not reset the seq counter');
    });

    test('caps frames at 5', () {
      final ErrorRingBuffer buf =
          ErrorRingBuffer(capacity: 3, sessionClock: sw);
      // Synthesize a long trace string with 10 newline-separated frames.
      final StackTrace fake = StackTrace.fromString(
          List<String>.generate(10, (int i) => '#$i frame $i').join('\n'));
      final ErrorEntry entry = buf.add('x', fake);
      expect(entry.frames.length, 5);
      expect(entry.frames.first, '#0 frame 0');
      expect(entry.frames.last, '#4 frame 4');
    });

    test('handles null stack as zero frames', () {
      final ErrorRingBuffer buf =
          ErrorRingBuffer(capacity: 3, sessionClock: sw);
      final ErrorEntry e = buf.add('x', null);
      expect(e.frames, isEmpty);
    });

    test('entriesSince returns suffix strictly newer than cursor', () {
      final ErrorRingBuffer buf =
          ErrorRingBuffer(capacity: 10, sessionClock: sw);
      buf.add('a', null);
      buf.add('b', null);
      buf.add('c', null);
      expect(buf.entriesSince(0).map((ErrorEntry e) => e.seq).toList(),
          <int>[1, 2, 3]);
      expect(buf.entriesSince(2).map((ErrorEntry e) => e.seq).toList(),
          <int>[3]);
      expect(buf.entriesSince(3), isEmpty);
      expect(buf.entriesSince(99), isEmpty);
    });

    test('entriesSince across an eviction', () {
      final ErrorRingBuffer buf =
          ErrorRingBuffer(capacity: 2, sessionClock: sw);
      buf.add('a', null); // seq 1
      buf.add('b', null); // seq 2
      buf.add('c', null); // seq 3 -> evicts seq 1
      // Caller had cursor=0 (never seen anything). Suffix is what's still
      // retained: seq 2 and 3.
      final List<ErrorEntry> got = buf.entriesSince(0);
      expect(got.map((ErrorEntry e) => e.seq).toList(), <int>[2, 3]);
    });

    test('toJson shape matches the documented schema', () {
      final ErrorRingBuffer buf =
          ErrorRingBuffer(capacity: 3, sessionClock: sw);
      final ErrorEntry e = buf.add('boom', StackTrace.fromString('#0 a'));
      final Map<String, Object?> json = e.toJson();
      expect(json.keys.toSet(),
          <String>{'seq', 'message', 'frames', 'wallClockOffsetMs'});
      expect(json['seq'], 1);
      expect(json['message'], 'boom');
      expect(json['frames'], <String>['#0 a']);
      expect(json['wallClockOffsetMs'], isA<int>());
    });

    test('wallClockOffsetMs uses provided session clock', () async {
      final Stopwatch clock = Stopwatch()..start();
      final ErrorRingBuffer buf =
          ErrorRingBuffer(capacity: 3, sessionClock: clock);
      final ErrorEntry first = buf.add('a', null);
      // Spin briefly to advance the clock.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final ErrorEntry second = buf.add('b', null);
      expect(second.wallClockOffsetMs, greaterThanOrEqualTo(first.wallClockOffsetMs));
    });
  });
}
