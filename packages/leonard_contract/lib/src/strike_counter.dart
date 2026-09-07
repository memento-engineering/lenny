/// Tracks consecutive failures against a configurable strike limit.
class StrikeCounter {
  /// Creates a counter that trips after [limit] consecutive failures.
  StrikeCounter({required this.limit});

  /// The number of consecutive failures that trips this counter.
  final int limit;

  int _consecutive = 0;

  /// Whether the consecutive failure count has reached [limit].
  bool get isTripped => _consecutive >= limit;

  /// Records one consecutive failure.
  void recordFailure() => _consecutive++;

  /// Resets the consecutive failure count.
  void recordSuccess() => _consecutive = 0;
}
