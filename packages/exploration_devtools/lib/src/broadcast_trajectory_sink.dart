import 'dart:async';
import 'dart:convert';

import 'package:exploration_agent/exploration_agent.dart';

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
  bool _closed = false;

  /// Live broadcast of every record the writer hands to [writeLine].
  Stream<TrajectoryRecord> get records => _ctrl.stream;

  @override
  Future<void> writeLine(String line) async {
    if (_closed) {
      throw StateError('BroadcastTrajectorySink is closed');
    }
    final Map<String, dynamic> json =
        jsonDecode(line) as Map<String, dynamic>;
    _ctrl.add(TrajectoryRecord.fromJson(json));
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
