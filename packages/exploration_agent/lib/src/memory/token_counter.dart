/// Token counting interface used by [RunningSummary] to enforce caps.
///
/// Real providers do their own server-side accounting; this interface only
/// exists so the harness can apply local soft/hard caps deterministically
/// (PRD §13). Tests inject a fake counter to fully control behaviour.
library;

/// Returns an integer token count for [text].
abstract interface class TokenCounter {
  /// Count the tokens in [text]. Implementations must be deterministic.
  int count(String text);
}

/// Naive whitespace-and-punctuation token counter.
///
/// Adequate for cap enforcement in the running summary. Empty input yields
/// `0`; otherwise the input is trimmed and split on runs of whitespace.
class WhitespaceTokenCounter implements TokenCounter {
  const WhitespaceTokenCounter();

  @override
  int count(String text) {
    if (text.isEmpty) return 0;
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).length;
  }
}
