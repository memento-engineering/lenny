import 'package:meta/meta.dart';

/// Immutable snapshot of framework-level "busy" signals captured by
/// `ExplorationBinding.frameworkBusySnapshot()`.
///
/// Consumed by the stable-observation primitive (cx6.8) and the timeline
/// serializer (cx6.10). JSON keys align with the PRD §9.2 `framework_busy`
/// schema so cx6.8 does not need to translate field names.
@immutable
class FrameworkBusySnapshot {
  const FrameworkBusySnapshot({
    required this.transientCallbacks,
    required this.persistentCallbacks,
    required this.pendingMicrotasks,
    required this.lastFrameCommitTimestamp,
    required this.recentSkippedFrames,
    required this.recentFrameCommits,
  });

  /// Number of transient frame callbacks scheduled but not yet fired.
  final int transientCallbacks;

  /// Number of persistent frame callbacks currently registered.
  final int persistentCallbacks;

  /// Best-effort edge signal: `true` iff at least one microtask has been
  /// scheduled in the current event-loop turn and has not yet run.
  final bool pendingMicrotasks;

  /// Timestamp of the most recent frame commit, or `null` if no frame has
  /// committed since the binding was installed.
  final Duration? lastFrameCommitTimestamp;

  /// Skipped-frame counter. Increments when a frame interval exceeds the
  /// scheduler skip threshold; resets after a full ring of on-time frames.
  final int recentSkippedFrames;

  /// Bounded ring buffer of recent frame commit timestamps. Read-only view;
  /// length is capped (current cap = 16).
  final List<Duration> recentFrameCommits;

  /// `true` iff any of the framework-level signals indicate the framework
  /// is doing work this turn.
  bool get isAnyBusy =>
      transientCallbacks > 0 ||
      persistentCallbacks > 0 ||
      pendingMicrotasks;

  /// JSON representation aligned with PRD §9.2 `framework_busy`. The
  /// `recent_frame_commits_us` field is intentionally omitted from this
  /// payload — the host's serializer (cx6.10) projects whichever ring
  /// fields it needs from `recentFrameCommits`.
  Map<String, Object?> toJson() => <String, Object?>{
        'transient_callbacks': transientCallbacks,
        'persistent_callbacks': persistentCallbacks,
        'microtasks': pendingMicrotasks,
        'last_frame_commit_us': lastFrameCommitTimestamp?.inMicroseconds,
        'recent_skipped_frames': recentSkippedFrames,
      };

  /// Canonical zero-valued snapshot. Returned by
  /// `ExplorationBinding.frameworkBusySnapshot()` in release mode and
  /// before any frames have committed.
  static const FrameworkBusySnapshot zero = FrameworkBusySnapshot(
    transientCallbacks: 0,
    persistentCallbacks: 0,
    pendingMicrotasks: false,
    lastFrameCommitTimestamp: null,
    recentSkippedFrames: 0,
    recentFrameCommits: <Duration>[],
  );
}
