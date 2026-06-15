/// `dart:io`-backed [TrajectorySink] for the CLI frontend.
///
/// Lives outside `package:leonard_agent` because that library is
/// web-compatible and must not import `dart:io`. Pairs with the
/// DevTools-side DTD sink (cx6.21).
library;

import 'dart:convert';
import 'dart:io';

import 'package:leonard_agent/leonard_agent.dart' show TrajectorySink;
import 'package:path/path.dart' as p;

/// Append-only JSONL sink that writes to a regular filesystem path.
///
/// Records are flushed after every write so a crashed session preserves
/// progress through the last fully-written line (PRD §14).
class FileTrajectorySink implements TrajectorySink {
  FileTrajectorySink._(this._sink, this.path);

  final IOSink _sink;

  /// Filesystem path the sink writes to.
  final String path;

  bool _closed = false;

  /// Open a sink at [path]. Creates parent directories as needed and
  /// appends if the file already exists.
  static Future<FileTrajectorySink> open(String path) async {
    final File f = File(path);
    await f.parent.create(recursive: true);
    final IOSink sink = f.openWrite(mode: FileMode.append, encoding: utf8);
    return FileTrajectorySink._(sink, path);
  }

  @override
  Future<void> writeLine(String line) async {
    _sink.writeln(line);
  }

  @override
  Future<void> flush() async {
    if (_closed) return;
    await _sink.flush();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sink.flush();
    await _sink.close();
  }

  /// `./trajectories/<UTC-timestamp>.jsonl` per the bead's contract.
  /// Timestamp pattern is `YYYYMMDDTHHMMSSZ`. Exposed for tests so the
  /// timestamp is deterministic.
  static String defaultOutputPath({DateTime? now}) {
    final DateTime t = (now ?? DateTime.now().toUtc()).toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    final String stamp = '${t.year}${two(t.month)}${two(t.day)}T'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
    return p.join('trajectories', '$stamp.jsonl');
  }
}
