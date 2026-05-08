import 'dart:convert';

import 'package:dtd/dtd.dart';
import 'package:exploration_agent/exploration_agent.dart';
import 'package:json_rpc_2/json_rpc_2.dart' show RpcException;

/// Reads `uri` and returns the file contents (or `null` if missing).
typedef DtdReadString = Future<String?> Function(Uri uri);

/// Overwrites `uri` with `contents`.
typedef DtdWriteString = Future<void> Function(Uri uri, String contents);

/// [TrajectorySink] backed by the Dart Tooling Daemon's filesystem service.
///
/// DTD has no append primitive, so each [writeLine] reads the existing file
/// and writes back the concatenation; this preserves the per-record flush
/// invariant required by `TrajectoryWriter` while staying free of `dart:io`
/// (the DevTools panel runs in a browser).
class DtdTrajectorySink implements TrajectorySink {
  /// Construct from raw read/write callbacks. Tests use this directly.
  DtdTrajectorySink({
    required Uri uri,
    required DtdReadString read,
    required DtdWriteString write,
  })  : _uri = uri,
        _read = read,
        _write = write;

  /// Wraps a live [DartToolingDaemon] connection. Translates a missing-file
  /// `RpcException` into a `null` read so the first append starts a fresh
  /// JSONL log.
  factory DtdTrajectorySink.fromDaemon(DartToolingDaemon dtd, Uri uri) {
    return DtdTrajectorySink(
      uri: uri,
      read: (u) async {
        try {
          final file = await dtd.readFileAsString(u, encoding: utf8);
          return file.content ?? '';
        } on RpcException catch (e) {
          if (e.code == RpcErrorCodes.kFileDoesNotExist) {
            return null;
          }
          rethrow;
        }
      },
      write: (u, contents) =>
          dtd.writeFileAsString(u, contents, encoding: utf8),
    );
  }

  final Uri _uri;
  final DtdReadString _read;
  final DtdWriteString _write;
  bool _closed = false;

  @override
  Future<void> writeLine(String line) async {
    if (_closed) {
      throw StateError('DtdTrajectorySink is closed');
    }
    final previous = await _read(_uri) ?? '';
    await _write(_uri, '$previous$line\n');
  }

  /// Each [writeLine] already round-trips through the daemon, so [flush] is
  /// a no-op.
  @override
  Future<void> flush() async {
    if (_closed) {
      throw StateError('DtdTrajectorySink is closed');
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}
