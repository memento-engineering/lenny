/// Ring buffer of recent runtime errors captured by the binding. Each
/// entry has a monotonically increasing [seq] so callers can request the
/// suffix using a "since" cursor.
library;

/// A single recorded runtime error.
///
/// Frames are capped at the first 5 stack frames; [wallClockOffsetMs] is
/// measured from the binding's session-start anchor.
class ErrorEntry {
  ErrorEntry({
    required this.seq,
    required this.message,
    required this.frames,
    required this.wallClockOffsetMs,
  });

  /// Monotonically increasing sequence number, starting at 1.
  final int seq;

  /// Stringified exception message (typically
  /// `FlutterErrorDetails.exceptionAsString()`).
  final String message;

  /// First 5 stack frames as raw strings (no allocation churn beyond a
  /// `split` + `take`).
  final List<String> frames;

  /// Milliseconds elapsed since the binding's session-start anchor.
  final int wallClockOffsetMs;

  Map<String, Object?> toJson() => <String, Object?>{
        'seq': seq,
        'message': message,
        'frames': frames,
        'wallClockOffsetMs': wallClockOffsetMs,
      };
}

/// Bounded drop-oldest ring buffer. Capacity is fixed at construction;
/// the (capacity+1)th add evicts entry 0.
///
/// Internally tracks a monotonically increasing `seq` so callers can
/// request entries strictly newer than a previously observed cursor.
class ErrorRingBuffer {
  ErrorRingBuffer({required this.capacity, required Stopwatch sessionClock})
      : assert(capacity > 0, 'capacity must be > 0'),
        _sessionClock = sessionClock;

  /// Maximum number of retained entries.
  final int capacity;

  final Stopwatch _sessionClock;
  final List<ErrorEntry> _ring = <ErrorEntry>[];
  int _nextSeq = 1;

  /// Highest seq observed so far. 0 if empty.
  int get highestSeq => _nextSeq - 1;

  /// Currently retained entries, oldest-first.
  List<ErrorEntry> get entries => List<ErrorEntry>.unmodifiable(_ring);

  /// Append a new entry. The oldest entry is evicted if at capacity.
  ErrorEntry add(String message, StackTrace? stack) {
    final List<String> frames = (stack?.toString() ?? '')
        .split('\n')
        .where((String s) => s.isNotEmpty)
        .take(5)
        .toList(growable: false);
    final ErrorEntry entry = ErrorEntry(
      seq: _nextSeq++,
      message: message,
      frames: frames,
      wallClockOffsetMs: _sessionClock.elapsedMilliseconds,
    );
    _ring.add(entry);
    if (_ring.length > capacity) {
      _ring.removeAt(0);
    }
    return entry;
  }

  /// Return entries with `seq > sinceSeq`, oldest-first.
  List<ErrorEntry> entriesSince(int sinceSeq) {
    return _ring
        .where((ErrorEntry e) => e.seq > sinceSeq)
        .toList(growable: false);
  }
}
