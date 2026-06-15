/// JSONL trace writer adapter for the dogfood harness
/// (bead lenny-cx6.43).
///
/// Thin wrapper that turns per-turn dogfood events into JSONL lines on
/// a caller-supplied `TrajectorySink`. The dogfood shape is distinct
/// from the canonical `TrajectoryWriter` records (session header /
/// turn / footer) because the harness needs a free-form per-turn
/// snapshot for prompt-tuning diffs — including raw prompt text,
/// provider decision, and binding-fake response.
library;

import 'dart:convert';

import '../provider/types.dart' show ToolDescriptor;
import '../trajectory/sink.dart';

/// Writes the three-record dogfood trace envelope: one
/// `dogfood_header`, N `dogfood_turn`s, one `dogfood_footer`.
///
/// The writer asserts that callers honor `header → turns* → footer`
/// ordering; close-on-footer makes the sink idempotent so a partially
/// written trace (e.g. when a typed exception aborts mid-run) still
/// closes cleanly.
class DogfoodTraceWriter {
  DogfoodTraceWriter(this._sink, this.path);

  final TrajectorySink _sink;

  /// Source path string echoed back in `DogfoodRunResult.tracePath`.
  /// Used for diagnostics only — the writer never reads it.
  final String path;

  bool _headerWritten = false;
  bool _footerWritten = false;

  /// Append the trace's `dogfood_header` line and flush.
  Future<void> writeHeader({
    required String goal,
    required String model,
    required List<ToolDescriptor> tools,
  }) async {
    if (_headerWritten) {
      throw StateError('DogfoodTraceWriter: header already written');
    }
    _headerWritten = true;
    await _sink.writeLine(jsonEncode(<String, Object?>{
      'type': 'dogfood_header',
      'goal': goal,
      'model': model,
      'tools': <Map<String, Object?>>[
        for (final ToolDescriptor t in tools)
          <String, Object?>{
            'name': t.name,
            'description': t.description,
          },
      ],
      'started_at': DateTime.now().toUtc().toIso8601String(),
    }));
    await _sink.flush();
  }

  /// Append one `dogfood_turn` line. Requires [writeHeader] to have
  /// completed; rejects further writes after [writeFooter].
  Future<void> writeTurn({
    required int index,
    required String prompt,
    required Map<String, dynamic>? decision,
    required Map<String, dynamic>? actResult,
    required int elapsedMs,
    String? error,
  }) async {
    if (!_headerWritten) {
      throw StateError('DogfoodTraceWriter: writeHeader() first');
    }
    if (_footerWritten) {
      throw StateError('DogfoodTraceWriter: footer already written');
    }
    await _sink.writeLine(jsonEncode(<String, Object?>{
      'type': 'dogfood_turn',
      'index': index,
      'prompt': prompt,
      'decision': decision,
      'act_result': actResult,
      'elapsed_ms': elapsedMs,
      if (error != null) 'error': error,
    }));
    await _sink.flush();
  }

  /// Append the trace's `dogfood_footer` line, flush, and close the
  /// underlying sink. Idempotent — repeated calls are no-ops so a
  /// caller-side try/finally can always invoke this safely.
  ///
  /// [exception] carries the **original** turn-level failure
  /// (TurnTimeoutError, SchemaRejection, …). [harnessError] carries
  /// the wire name of the [HarnessError] sub-classification when the
  /// LoopDriver returned a `SessionTermination` with a non-null
  /// `harnessError` (e.g. `connection_lost`, `agent_stuck`); the
  /// human-readable text remains on [exception] so existing readers
  /// stay unchanged, and the enum value lives on `harness_error` for
  /// filterability (lenny-cx6.45). [recoveryError] is the secondary
  /// exception (if any) raised from the harness's own cleanup path —
  /// surfaced separately so downstream readers can distinguish "the
  /// run failed because X" from "the run failed because X and
  /// recovery itself also failed with Y". The harness must not let a
  /// secondary error overwrite the original.
  Future<void> writeFooter({
    required String outcome,
    String? exception,
    String? harnessError,
    String? recoveryError,
  }) async {
    if (_footerWritten) return;
    // NB: _footerWritten is set **after** the sink write succeeds.
    // If the sink throws, the caller may retry (e.g. with a populated
    // [recoveryError]) and we will still emit one footer line.
    if (!_headerWritten) {
      // Defensive: write a degenerate header so the trace remains
      // parseable even if the harness aborts before the header path
      // runs. This keeps the JSONL invariant `header ; turn* ; footer`
      // intact for downstream readers.
      _headerWritten = true;
      await _sink.writeLine(jsonEncode(<String, Object?>{
        'type': 'dogfood_header',
        'goal': '',
        'model': '',
        'tools': <Map<String, Object?>>[],
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'synthetic': true,
      }));
      await _sink.flush();
    }
    await _sink.writeLine(jsonEncode(<String, Object?>{
      'type': 'dogfood_footer',
      'outcome': outcome,
      if (exception != null) 'exception': exception,
      if (harnessError != null) 'harness_error': harnessError,
      if (recoveryError != null) 'recovery_error': recoveryError,
      'ended_at': DateTime.now().toUtc().toIso8601String(),
    }));
    await _sink.flush();
    _footerWritten = true;
    await _sink.close();
  }
}
