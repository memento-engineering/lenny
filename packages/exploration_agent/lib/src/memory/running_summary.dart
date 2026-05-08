/// Running-summary memory artifact (PRD §13).
///
/// Holds the model-authored summary of the run so far. The summary is
/// re-written each turn by the model. Two caps are enforced via an injected
/// [TokenCounter]:
///
/// - **Soft cap** (default 500 tokens): observable via [softCapExceeded].
///   The harness uses this to nudge the model toward shrinking the summary.
/// - **Hard cap** (default 1000 tokens): exceeding it throws
///   [SummaryOversizeError] and the previous summary is retained.
library;

import 'token_counter.dart';

/// Thrown by [RunningSummary.update] when the new summary's token count
/// exceeds the configured hard cap. Carries both the offending count and
/// the cap so the loop driver can surface a meaningful error.
class SummaryOversizeError extends Error {
  SummaryOversizeError({required this.tokenCount, required this.cap});

  /// Token count of the oversize update (as measured by the injected
  /// [TokenCounter]).
  final int tokenCount;

  /// The hard cap that was violated.
  final int cap;

  @override
  String toString() =>
      'SummaryOversizeError: $tokenCount tokens > cap=$cap';
}

/// Mutable container for the running summary.
class RunningSummary {
  RunningSummary({
    required TokenCounter counter,
    this.softCap = 500,
    this.hardCap = 1000,
  })  : assert(softCap > 0, 'softCap must be positive'),
        assert(hardCap >= softCap, 'hardCap must be >= softCap'),
        _counter = counter;

  final TokenCounter _counter;

  /// Soft-cap token threshold. Updates above this set [softCapExceeded].
  final int softCap;

  /// Hard-cap token threshold. Updates above this throw
  /// [SummaryOversizeError] and the previous summary is retained.
  final int hardCap;

  String _text = '';
  bool _softCapExceeded = false;

  /// Current summary text. Empty until the first successful [update].
  String get text => _text;

  /// `true` when the most recent successful update's token count exceeded
  /// [softCap] (but was within [hardCap]).
  bool get softCapExceeded => _softCapExceeded;

  /// Replace the running summary with [text].
  ///
  /// Throws [SummaryOversizeError] when the token count exceeds [hardCap]
  /// — in that case the prior summary is left unchanged.
  void update(String text) {
    final int n = _counter.count(text);
    if (n > hardCap) {
      throw SummaryOversizeError(tokenCount: n, cap: hardCap);
    }
    _text = text;
    _softCapExceeded = n > softCap;
  }
}
