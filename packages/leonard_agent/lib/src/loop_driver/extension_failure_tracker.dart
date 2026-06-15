/// Tracks consecutive observation failures per plugin namespace.
///
/// PRD §17: a plugin that throws three times in a row during
/// `observe()`/`busyState()`/`onActionExecuted` is auto-disabled by the
/// driver. Counters reset on a successful (non-error) observation
/// fragment. Tracking is per-plugin — one plugin's flakes never
/// interfere with another's counter.
library;

class ExtensionFailureTracker {
  /// PRD §17 threshold — auto-disable after three consecutive failures
  /// from the same plugin.
  static const int autoDisableThreshold = 3;

  final Map<String, int> _counts = <String, int>{};

  /// Record a failure for [namespace]. Returns `true` iff this failure
  /// brings the consecutive-failure count to (or above)
  /// [autoDisableThreshold] — i.e. the caller should auto-disable on
  /// this turn. Returns `false` for the first and second failures.
  ///
  /// The counter is *not* reset on the auto-disable transition; the
  /// driver removes the plugin from the active set on the next turn,
  /// so the counter ceases to advance naturally.
  bool recordFailure(String namespace) {
    final int n = (_counts[namespace] ?? 0) + 1;
    _counts[namespace] = n;
    return n >= autoDisableThreshold;
  }

  /// Reset the consecutive-failure counter for [namespace].
  void recordSuccess(String namespace) {
    _counts[namespace] = 0;
  }

  /// Current consecutive-failure count for [namespace] (0 if absent).
  int failuresFor(String namespace) => _counts[namespace] ?? 0;
}
