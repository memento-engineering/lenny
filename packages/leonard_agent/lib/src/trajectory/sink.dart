/// Append-only line sink for trajectory writers. Implementations live
/// outside `leonard_agent` (e.g. `FileTrajectorySink` using `dart:io`
/// in the CLI, `DtdTrajectorySink` using `package:dtd` in DevTools).
///
/// Signatures must remain free of `dart:io` types so this library stays
/// web-compatible.
abstract class TrajectorySink {
  /// Append one line. The writer adds the trailing newline.
  Future<void> writeLine(String line);

  /// Force buffered bytes to durable storage.
  Future<void> flush();

  /// Flush and release the underlying handle. Idempotent.
  Future<void> close();
}
