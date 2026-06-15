import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'framework_busy_snapshot.dart';

/// Mixin layered onto `SchedulerBinding` (via `LeonardBinding`) that
/// observes framework-level "busy" signals: in-flight transient callbacks,
/// registered persistent callbacks, pending microtasks (best effort), and
/// frame-commit / skipped-frame timestamps.
///
/// All counters are bounded; the only collection that grows is a fixed-cap
/// ring buffer of recent commit timestamps. The hooks are gated to
/// `kDebugMode || kProfileMode`; in release mode the overrides degrade to
/// simple `super` delegation and `frameworkBusySnapshot()` returns
/// `FrameworkBusySnapshot.zero`.
mixin FrameStabilityTracker on SchedulerBinding {
  /// Maximum number of frame-commit timestamps retained in the ring buffer.
  static const int _commitRingCap = 16;

  /// Two times the nominal 60Hz vsync budget, used to flag a "skipped"
  /// inter-frame interval per PRD §6.1.
  static const Duration _skipThreshold = Duration(milliseconds: 33);

  int _transientInFlight = 0;
  int _persistentRegistered = 0;
  bool _microtaskPending = false;
  Duration? _lastCommit;
  final List<Duration> _commits = <Duration>[];
  int _recentSkipped = 0;
  int _consecutiveOnTime = 0;

  bool get _enabled => kDebugMode || kProfileMode;

  /// Returns a synchronous, immutable snapshot of the current
  /// framework-level busy signals. In release mode returns
  /// `FrameworkBusySnapshot.zero`.
  ///
  /// The returned object's `recentFrameCommits` is a fresh unmodifiable
  /// view over the bounded internal ring; the ring itself never exceeds
  /// `_commitRingCap` elements regardless of polling frequency.
  FrameworkBusySnapshot frameworkBusySnapshot() {
    if (!_enabled) return FrameworkBusySnapshot.zero;
    return FrameworkBusySnapshot(
      transientCallbacks: _transientInFlight,
      persistentCallbacks: _persistentRegistered,
      pendingMicrotasks: _microtaskPending,
      lastFrameCommitTimestamp: _lastCommit,
      recentSkippedFrames: _recentSkipped,
      recentFrameCommits: List<Duration>.unmodifiable(_commits),
    );
  }

  /// Convenience getter: `true` iff any tracked signal indicates the
  /// framework is doing work this turn.
  bool get isAnyFrameworkSignalBusy =>
      _enabled &&
      (_transientInFlight > 0 ||
          _persistentRegistered > 0 ||
          _microtaskPending);

  @override
  int scheduleFrameCallback(
    FrameCallback callback, {
    bool rescheduling = false,
    bool scheduleNewFrame = true,
  }) {
    if (!_enabled) {
      return super.scheduleFrameCallback(
        callback,
        rescheduling: rescheduling,
        scheduleNewFrame: scheduleNewFrame,
      );
    }
    _transientInFlight++;
    return super.scheduleFrameCallback(
      (Duration ts) {
        try {
          callback(ts);
        } finally {
          if (_transientInFlight > 0) _transientInFlight--;
        }
      },
      rescheduling: rescheduling,
      scheduleNewFrame: scheduleNewFrame,
    );
  }

  @override
  void addPersistentFrameCallback(FrameCallback callback) {
    if (_enabled) _persistentRegistered++;
    super.addPersistentFrameCallback(callback);
  }

  /// Records that a microtask has been scheduled by the user-mode app.
  /// Wired by `LeonardBinding.stabilityZoneSpec` via a
  /// `ZoneSpecification.scheduleMicrotask` interceptor; tests may also
  /// call this directly. The flag flips back to `false` on the next
  /// microtask boundary.
  ///
  /// Internal to the `leonard_flutter` package — not exported. The
  /// reset microtask is scheduled via `Zone.root` so it cannot be
  /// re-intercepted by the stability `ZoneSpecification` (which would
  /// otherwise recurse).
  void markMicrotaskScheduled() {
    if (!_enabled) return;
    _microtaskPending = true;
    Zone.root.scheduleMicrotask(() {
      _microtaskPending = false;
    });
  }

  @override
  void handleDrawFrame() {
    // SchedulerBinding.handleDrawFrame() nulls _currentFrameTimeStamp at
    // the end of the method, so we capture the timestamp first, run the
    // real frame, then update bookkeeping. Reading the timestamp via the
    // public getter triggers an assert if the binding is not currently
    // mid-frame, which would only happen in release-mode short-circuits
    // we have already returned from.
    if (!_enabled) {
      super.handleDrawFrame();
      return;
    }
    final Duration ts = currentFrameTimeStamp;
    super.handleDrawFrame();
    if (_lastCommit != null) {
      final Duration delta = ts - _lastCommit!;
      if (delta > _skipThreshold) {
        _recentSkipped++;
        _consecutiveOnTime = 0;
      } else {
        _consecutiveOnTime++;
        if (_consecutiveOnTime >= _commitRingCap && _recentSkipped > 0) {
          _recentSkipped = 0;
        }
      }
    }
    _lastCommit = ts;
    _commits.add(ts);
    if (_commits.length > _commitRingCap) {
      _commits.removeAt(0);
    }
  }
}
