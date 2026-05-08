/// Append-only text buffer that notifies listeners with a version
/// counter so a single leaf [ValueListenableBuilder] rebuilds per token
/// (the rest of the widget tree stays put).
///
/// Web-compatible: pure Flutter / Dart, no `dart:io`.
library;

import 'package:flutter/foundation.dart';

/// A `ValueNotifier<int>` whose value increments each time a non-empty
/// chunk is appended (or the buffer is cleared). The actual text is
/// exposed via [text]; the int is just a rebuild signal.
class AppendOnlyTextController extends ValueNotifier<int> {
  AppendOnlyTextController() : super(0);

  final StringBuffer _buf = StringBuffer();

  /// Current accumulated text.
  String get text => _buf.toString();

  /// Length of the accumulated text in code units.
  int get length => _buf.length;

  /// Append [chunk] to the buffer and bump the version counter.
  /// Empty chunks are no-ops (do not notify).
  void append(String chunk) {
    if (chunk.isEmpty) return;
    _buf.write(chunk);
    value = value + 1;
  }

  /// Clear the buffer and bump the version counter.
  void clear() {
    if (_buf.isEmpty) {
      // Still bump so listeners can react to a turn boundary even when
      // nothing was streamed for the previous turn.
      value = value + 1;
      return;
    }
    _buf.clear();
    value = value + 1;
  }
}
