import 'dart:convert';

import 'records.dart';
import 'sink.dart';

/// Serializes typed trajectory records to JSONL via a [TrajectorySink].
///
/// PRD §14 requires per-record recovery: every write is followed by
/// `flush()` so a crashed session preserves progress through the last
/// fully-written record. `close()` always emits the footer (even on
/// `harness_error`) and is idempotent; the loop driver wraps its
/// outermost try/finally around `close()`.
class TrajectoryWriter {
  final TrajectorySink _sink;
  bool _closed = false;
  bool _headerWritten = false;

  TrajectoryWriter(this._sink);

  Future<void> writeHeader(SessionHeader h) async {
    _ensureOpen();
    if (_headerWritten) {
      throw StateError('Trajectory header already written');
    }
    _headerWritten = true;
    await _writeAndFlush(h.toJson());
  }

  Future<void> writeTurn(TurnRecord t) async {
    _ensureOpen();
    _ensureHeader();
    await _writeAndFlush(t.toJson());
  }

  Future<void> writeExtensionDisabled(ExtensionDisabledEvent e) async {
    _ensureOpen();
    _ensureHeader();
    await _writeAndFlush(e.toJson());
  }

  Future<void> close(SessionFooter footer) async {
    if (_closed) return;
    _closed = true;
    await _writeAndFlush(footer.toJson());
    await _sink.close();
  }

  Future<void> _writeAndFlush(Map<String, dynamic> j) async {
    await _sink.writeLine(jsonEncode(j));
    await _sink.flush();
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('TrajectoryWriter is closed');
    }
  }

  void _ensureHeader() {
    if (!_headerWritten) {
      throw StateError('writeHeader must precede turns/events');
    }
  }
}
