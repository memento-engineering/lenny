import 'dart:async';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:flutter/foundation.dart';

/// Source of [TrajectoryRecord]s rendered by [TimelinePanel].
///
/// Two implementations are shipped:
///
/// * [LiveTimelineSource] — subscribes to a `Stream<TrajectoryRecord>`
///   from the in-panel `TrajectoryWriter` and appends rows as the
///   session progresses.
/// * [BrowseTimelineSource] — hydrates the full record list from a
///   JSONL document loaded via DTD's filesystem service.
abstract class TimelineSource {
  /// Append-only list of records observed so far. Always reassigned to
  /// a new unmodifiable list when a record arrives so listeners
  /// (notably `ValueListenableBuilder`) see a value change.
  ValueListenable<List<TrajectoryRecord>> get records;

  /// Releases any resources held by the source. Idempotent.
  Future<void> close();
}

/// [TimelineSource] that grows live as records arrive on a stream.
class LiveTimelineSource implements TimelineSource {
  final ValueNotifier<List<TrajectoryRecord>> _list =
      ValueNotifier<List<TrajectoryRecord>>(const []);
  StreamSubscription<TrajectoryRecord>? _sub;
  bool _closed = false;

  LiveTimelineSource(Stream<TrajectoryRecord> source) {
    _sub = source.listen((record) {
      if (_closed) return;
      _list.value = List<TrajectoryRecord>.unmodifiable([
        ..._list.value,
        record,
      ]);
    });
  }

  @override
  ValueListenable<List<TrajectoryRecord>> get records => _list;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub?.cancel();
    _sub = null;
    _list.dispose();
  }
}

/// [TimelineSource] that loads its records from a JSONL document.
class BrowseTimelineSource implements TimelineSource {
  final ValueNotifier<List<TrajectoryRecord>> _list;
  bool _closed = false;

  BrowseTimelineSource.fromJsonl(String jsonl)
    : _list = ValueNotifier<List<TrajectoryRecord>>(
        List<TrajectoryRecord>.unmodifiable(TrajectoryReader.readAll(jsonl)),
      );

  /// Test/perf escape hatch: build directly from an in-memory list.
  BrowseTimelineSource.fromRecords(List<TrajectoryRecord> records)
    : _list = ValueNotifier<List<TrajectoryRecord>>(
        List<TrajectoryRecord>.unmodifiable(records),
      );

  @override
  ValueListenable<List<TrajectoryRecord>> get records => _list;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _list.dispose();
  }
}
