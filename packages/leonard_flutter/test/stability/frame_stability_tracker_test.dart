import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leonard_flutter/leonard_flutter.dart';

/// Drives one synthetic frame through the binding by calling
/// `handleBeginFrame` followed by `handleDrawFrame` at the given
/// timestamp. This is the same sequence the engine triggers and is what
/// `FrameStabilityTracker` observes.
void _runFrame(SchedulerBinding binding, Duration ts) {
  binding.handleBeginFrame(ts);
  binding.handleDrawFrame();
}

void main() {
  // LeonardBinding installs as the WidgetsBinding the first time
  // ensureInitialized runs in this isolate; subsequent calls are
  // idempotent. All tests in this file share it.
  late LeonardBinding binding;

  setUpAll(() {
    binding = LeonardBinding.ensureInitialized(extensions: const [])!;
    expect(
      WidgetsBinding.instance,
      same(binding),
      reason: 'precondition: LeonardBinding is the active binding',
    );
  });

  test('transient callback count tracks scheduling and firing', () {
    final int before = binding.frameworkBusySnapshot().transientCallbacks;
    binding.scheduleFrameCallback((_) {});
    expect(binding.frameworkBusySnapshot().transientCallbacks - before, 1);
    _runFrame(binding, const Duration(milliseconds: 100));
    expect(binding.frameworkBusySnapshot().transientCallbacks, before);
  });

  test('persistent callback count increments on add', () {
    final int start = binding.frameworkBusySnapshot().persistentCallbacks;
    binding.addPersistentFrameCallback((_) {});
    binding.addPersistentFrameCallback((_) {});
    expect(binding.frameworkBusySnapshot().persistentCallbacks - start, 2);
  });

  test('lastFrameCommitTimestamp updates after a frame', () {
    final Duration? before = binding
        .frameworkBusySnapshot()
        .lastFrameCommitTimestamp;
    // SchedulerBinding adjusts the timestamp by the epoch (the first frame
    // ever observed), so we assert that *some* timestamp lands rather than
    // any specific value. Subsequent frames must produce a strictly later
    // commit timestamp than the previous one.
    _runFrame(binding, const Duration(milliseconds: 90000));
    final Duration? after = binding
        .frameworkBusySnapshot()
        .lastFrameCommitTimestamp;
    expect(after, isNotNull);
    if (before != null) {
      expect(
        after! > before,
        isTrue,
        reason: 'commit timestamp must advance for a later frame',
      );
    }
  });

  test('recentFrameCommits ring is bounded to 16', () {
    for (int i = 0; i < 25; i++) {
      _runFrame(binding, Duration(milliseconds: 1000 + i * 16));
    }
    expect(binding.frameworkBusySnapshot().recentFrameCommits.length, 16);
  });

  test('recentSkippedFrames increments on a long inter-frame interval', () {
    // Establish a baseline frame, then jump >33ms to force a skip.
    _runFrame(binding, const Duration(milliseconds: 5000));
    final int before = binding.frameworkBusySnapshot().recentSkippedFrames;
    _runFrame(binding, const Duration(milliseconds: 5100));
    expect(
      binding.frameworkBusySnapshot().recentSkippedFrames,
      greaterThan(before),
    );
  });

  test('isAnyFrameworkSignalBusy reflects counters', () {
    // Drain any pending transient callbacks first.
    _runFrame(binding, const Duration(milliseconds: 6000));
    binding.scheduleFrameCallback((_) {});
    expect(binding.isAnyFrameworkSignalBusy, isTrue);
    _runFrame(binding, const Duration(milliseconds: 6100));
    // After the frame fires, the scheduled transient callback has run; assert
    // the transient contribution returned to zero. (Persistent callbacks no
    // longer count toward busy — see lenny-ndnp.)
    expect(binding.frameworkBusySnapshot().transientCallbacks, 0);
  });

  test('snapshot polling keeps ring buffer bounded', () {
    for (int i = 0; i < 1000; i++) {
      binding.frameworkBusySnapshot();
    }
    expect(
      binding.frameworkBusySnapshot().recentFrameCommits.length,
      lessThanOrEqualTo(16),
    );
  });

  test('returned recentFrameCommits is unmodifiable', () {
    final List<Duration> commits = binding
        .frameworkBusySnapshot()
        .recentFrameCommits;
    expect(() => commits.add(Duration.zero), throwsUnsupportedError);
  });
}
