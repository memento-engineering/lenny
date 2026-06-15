import 'package:flutter_test/flutter_test.dart';
import 'package:leonard_flutter/src/stability/framework_busy_snapshot.dart';

void main() {
  test('JSON keys match PRD §9.2 framework_busy schema', () {
    final j = FrameworkBusySnapshot.zero.toJson();
    expect(j['transient_callbacks'], 0);
    expect(j['persistent_callbacks'], 0);
    expect(j['microtasks'], false);
    expect(j['last_frame_commit_us'], isNull);
    expect(j['recent_skipped_frames'], 0);
  });

  test('JSON last_frame_commit_us projects microseconds, not milliseconds', () {
    const FrameworkBusySnapshot s = FrameworkBusySnapshot(
      transientCallbacks: 0,
      persistentCallbacks: 0,
      pendingMicrotasks: false,
      lastFrameCommitTimestamp: Duration(milliseconds: 7),
      recentSkippedFrames: 0,
      recentFrameCommits: <Duration>[],
    );
    expect(s.toJson()['last_frame_commit_us'], 7000);
  });
}
