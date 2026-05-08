/// Last-N actions ring buffer (PRD §13).
///
/// Records one-line outcomes of recent actions. The model sees these
/// verbatim in the assembled prompt's "Recent actions" section.
library;

/// Insertion-order capped recall of recent action lines.
class ActionRing {
  ActionRing({this.capacity = 5}) : assert(capacity > 0);

  /// Maximum number of entries retained.
  final int capacity;

  final List<String> _entries = <String>[];

  /// Most-recent-last view, capped at [capacity]. Read-only and
  /// safe to call before any push (returns empty).
  List<String> get entries => List<String>.unmodifiable(_entries);

  /// Append [entry]. When the ring is full, the oldest entry is dropped.
  void push(String entry) {
    _entries.add(entry);
    if (_entries.length > capacity) {
      _entries.removeAt(0);
    }
  }
}
