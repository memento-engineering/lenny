import 'dart:async';
import 'dart:convert';

import 'records.dart';

/// Decodes JSONL trajectories into [TrajectoryRecord]s.
///
/// Counterpart to [TrajectoryWriter]. Tolerates trailing newlines and
/// blank lines. Unknown `type` discriminators surface as
/// [UnknownTrajectoryRecord] so a reader from a future schema version
/// still renders the rest of the trajectory.
class TrajectoryReader {
  TrajectoryReader._();

  /// Parses a complete in-memory JSONL document.
  static List<TrajectoryRecord> readAll(String jsonl) {
    final lines = const LineSplitter().convert(jsonl);
    final out = <TrajectoryRecord>[];
    for (final line in lines) {
      if (line.isEmpty) continue;
      out.add(_parseLine(line));
    }
    return out;
  }

  /// Streams records from a line stream — useful for very large
  /// trajectories where buffering the entire file would be wasteful.
  static Stream<TrajectoryRecord> readStream(Stream<String> lines) =>
      lines.where((l) => l.isNotEmpty).map(_parseLine);

  static TrajectoryRecord _parseLine(String line) {
    final decoded = jsonDecode(line);
    if (decoded is! Map<String, dynamic>) {
      return UnknownTrajectoryRecord(
        rawType: 'non-object',
        raw: {'raw': decoded},
      );
    }
    return TrajectoryRecord.fromJson(decoded);
  }
}
