import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The on-device bug (lenny-whn): on a cold start the first semantics read
// races the flush that `ensureSemantics()` only schedules, so the root is
// momentarily null. The `flutter_test` harness cannot reproduce that race —
// after layout its semantics root is always synchronously available (a fresh
// harness already exposes a non-empty default tree). So these tests use the
// `debugRaceNextRootLookup` seam to inject exactly that one-shot null-root
// condition, then prove that `captureAsync()` recovers from it (awaits the
// frame and re-reads) while the deprecated synchronous `capture()` does not.
void main() {
  testWidgets(
    'sync capture() returns [] under the cold-start race (the bug captureAsync fixes)',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text('Go'))),
        ),
      );

      final SemanticsCapture cap = SemanticsCapture()
        ..debugRaceNextRootLookup = true;

      // The single root read is forced null → the sync path bails to [].
      // ignore: deprecated_member_use
      final List<Map<String, Object>> before = cap.capture();
      expect(
        before,
        isEmpty,
        reason: 'sync capture() does not wait for the flush → []',
      );

      cap.dispose();
    },
  );

  testWidgets(
    'captureAsync() awaits the frame and re-reads, recovering the populated tree',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text('Go'))),
        ),
      );

      final SemanticsCapture cap = SemanticsCapture()
        ..debugRaceNextRootLookup = true;

      // First root read is forced null (the race) → captureAsync() awaits
      // endOfFrame. In the automated binding endOfFrame only completes on an
      // explicit pump, so drive one frame concurrently; the second read then
      // returns the real, now-flushed tree.
      final Future<List<Map<String, Object>>> pending = cap.captureAsync();
      await tester.pump();
      final List<Map<String, Object>> after = await pending;

      // RED-ON-REVERT: if captureAsync() drops the endOfFrame await + retry
      // (i.e. behaves like the deprecated sync capture()), the forced-null
      // first read makes `after` empty and this fails.
      expect(
        after,
        isNotEmpty,
        reason: 'captureAsync() must recover the tree after awaiting the frame',
      );
      expect(
        after.any((Map<String, Object> r) => r['label'] == 'Go'),
        isTrue,
        reason: 'the Text("Go") node must be present after the flush completes',
      );

      cap.dispose();
    },
  );
}
