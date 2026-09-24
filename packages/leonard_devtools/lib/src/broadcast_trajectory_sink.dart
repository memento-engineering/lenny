import 'dart:async';
import 'dart:convert';

import 'package:leonard_agent/leonard_agent.dart';

/// In-memory [TrajectorySink] that re-broadcasts each JSONL line a
/// [TrajectoryWriter] writes through it as a parsed [TrajectoryRecord]
/// on the [records] stream.
///
/// Backs [PromptPanelController]'s in-flight writer so the DevTools
/// timeline tab can render records live as the loop emits them. The
/// disk-backed [DtdTrajectorySink] (already in this package) remains
/// the future production successor for persistence, but the panel
/// needs *some* writer to satisfy the AC that pressing Start renders
/// at least one TurnRecord in the timeline; in-memory fan-out is the
/// minimum that satisfies that.
class BroadcastTrajectorySink implements TrajectorySink {
  final StreamController<TrajectoryRecord> _ctrl =
      StreamController<TrajectoryRecord>.broadcast();
  final List<TrajectoryRecord> _history = <TrajectoryRecord>[];
  bool _closed = false;

  /// Every record the writer hands to [writeLine]: each listener first
  /// receives the session so far, then live records. The Timeline tab
  /// subscribes only when first opened, often after the run has emitted.
  Stream<TrajectoryRecord> get records => Stream<TrajectoryRecord>.multi((
    MultiStreamController<TrajectoryRecord> out,
  ) {
    _history.forEach(out.addSync);
    if (_closed) {
      out.closeSync();
      return;
    }
    final StreamSubscription<TrajectoryRecord> live = _ctrl.stream.listen(
      out.addSync,
      onError: out.addErrorSync,
      onDone: out.closeSync,
    );
    out.onCancel = live.cancel;
  });

  @override
  Future<void> writeLine(String line) async {
    if (_closed) {
      throw StateError('BroadcastTrajectorySink is closed');
    }
    final Map<String, dynamic> json = jsonDecode(line) as Map<String, dynamic>;
    final TrajectoryRecord record = TrajectoryRecord.fromJson(json);
    _history.add(record);
    _ctrl.add(record);
  }

  /// In-memory sink: nothing to flush.
  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _ctrl.close();
  }
}
