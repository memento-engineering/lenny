import 'package:flutter_test/flutter_test.dart';
import 'package:leonard_flutter/src/stability/framework_busy_snapshot.dart';

void main() {
  test('zero reports nothing busy', () {
    expect(FrameworkBusySnapshot.zero.isAnyBusy, isFalse);
    expect(FrameworkBusySnapshot.zero.transientCallbacks, 0);
    expect(FrameworkBusySnapshot.zero.persistentCallbacks, 0);
    expect(FrameworkBusySnapshot.zero.pendingMicrotasks, isFalse);
    expect(FrameworkBusySnapshot.zero.lastFrameCommitTimestamp, isNull);
    expect(FrameworkBusySnapshot.zero.recentSkippedFrames, 0);
    expect(FrameworkBusySnapshot.zero.recentFrameCommits, isEmpty);
  });

  test('isAnyBusy true when any signal nonzero/present', () {
    expect(
      const FrameworkBusySnapshot(
        transientCallbacks: 1,
        persistentCallbacks: 0,
        pendingMicrotasks: false,
        lastFrameCommitTimestamp: null,
        recentSkippedFrames: 0,
        recentFrameCommits: <Duration>[],
      ).isAnyBusy,
      isTrue,
    );
    expect(
      const FrameworkBusySnapshot(
        transientCallbacks: 0,
        persistentCallbacks: 1,
        pendingMicrotasks: false,
        lastFrameCommitTimestamp: null,
        recentSkippedFrames: 0,
        recentFrameCommits: <Duration>[],
      ).isAnyBusy,
      isTrue,
    );
    expect(
      const FrameworkBusySnapshot(
        transientCallbacks: 0,
        persistentCallbacks: 0,
        pendingMicrotasks: true,
        lastFrameCommitTimestamp: null,
        recentSkippedFrames: 0,
        recentFrameCommits: <Duration>[],
      ).isAnyBusy,
      isTrue,
    );
  });

  test('toJson keys match PRD §9.2', () {
    final j = FrameworkBusySnapshot.zero.toJson();
    expect(
      j.keys,
      containsAll(<String>[
        'transient_callbacks',
        'persistent_callbacks',
        'microtasks',
        'last_frame_commit_us',
        'recent_skipped_frames',
      ]),
    );
  });
}
