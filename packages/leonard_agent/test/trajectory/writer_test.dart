import 'dart:convert';

import 'package:leonard_agent/src/trajectory/records.dart';
import 'package:leonard_agent/src/trajectory/sink.dart';
import 'package:leonard_agent/src/trajectory/writer.dart';
import 'package:test/test.dart';

class _RecordingSink implements TrajectorySink {
  final List<String> lines = [];
  int flushCount = 0;
  int closeCount = 0;

  @override
  Future<void> writeLine(String line) async {
    lines.add(line);
  }

  @override
  Future<void> flush() async {
    flushCount++;
  }

  @override
  Future<void> close() async {
    closeCount++;
  }
}

SessionHeader _hdr() => const SessionHeader(
      goal: 'login',
      agentsMdHash: 'sha256:abc',
      buildIdentifier: 'debug-1.0.0',
      modelIdentifier: 'qwen3.6-35b-a3b@8bit',
      harnessVersion: '0.1.0',
      plugins: [
        ExtensionManifestRecord(
          namespace: 'router',
          packageVersion: '1.2.3',
          contractVersion: '1.0.0',
        ),
      ],
      config: {'turn_budget_ms': 30000},
    );

TurnRecord _turn(int i) => TurnRecord(
      index: i,
      observation: const {'core': <String, dynamic>{}, 'extensions': <String, dynamic>{}},
      stability: const {'policy': 'action_relative'},
      proposedAction: const {'tool': 'core.tap'},
      validation: const {'result': 'ok', 'retries': 0},
      executedAction: const {'tool': 'core.tap'},
      diff: const {'core': <String, dynamic>{}, 'extensions': <String, dynamic>{}},
      modelMetadata: const {
        'tokens_in': 10,
        'tokens_out': 5,
        'duration_ms': 200,
      },
    );

void main() {
  group('TrajectoryWriter', () {
    test('header + 2 turns + footer', () async {
      final sink = _RecordingSink();
      final w = TrajectoryWriter(sink);
      await w.writeHeader(_hdr());
      await w.writeTurn(_turn(0));
      await w.writeTurn(_turn(1));
      await w.close(const SessionFooter(
        outcome: SessionOutcome.done,
        totalTurns: 2,
        totalDurationMs: 1234,
      ));

      expect(sink.lines.length, 4);
      expect(sink.flushCount, 4);
      expect(sink.closeCount, 1);
      for (final l in sink.lines) {
        expect(l.contains('\n'), isFalse);
      }
      final types =
          sink.lines.map((l) => jsonDecode(l)['type'] as String).toList();
      expect(types, ['header', 'turn', 'turn', 'footer']);
    });

    test('extension_disabled between turns', () async {
      final sink = _RecordingSink();
      final w = TrajectoryWriter(sink);
      await w.writeHeader(_hdr());
      await w.writeTurn(_turn(0));
      await w.writeExtensionDisabled(const ExtensionDisabledEvent(
        namespace: 'dio',
        reason: 'auto_disabled_after_3_failures',
        turn: 1,
      ));
      await w.writeTurn(_turn(1));
      await w.close(const SessionFooter(
        outcome: SessionOutcome.done,
        totalTurns: 2,
        totalDurationMs: 100,
      ));

      expect(jsonDecode(sink.lines[2]), {
        'type': 'extension_disabled',
        'namespace': 'dio',
        'reason': 'auto_disabled_after_3_failures',
        'turn': 1,
      });
    });

    test('footer on harness_error', () async {
      final sink = _RecordingSink();
      final w = TrajectoryWriter(sink);
      await w.writeHeader(_hdr());
      await w.close(const SessionFooter(
        outcome: SessionOutcome.harnessError,
        totalTurns: 0,
        totalDurationMs: 50,
        harnessError: 'connection_lost',
      ));

      final last = jsonDecode(sink.lines.last) as Map<String, dynamic>;
      expect(last['type'], 'footer');
      expect(last['outcome'], 'harness_error');
      expect(last['harness_error'], 'connection_lost');
    });

    test('close idempotent', () async {
      final sink = _RecordingSink();
      final w = TrajectoryWriter(sink);
      await w.writeHeader(_hdr());
      const footer = SessionFooter(
        outcome: SessionOutcome.done,
        totalTurns: 0,
        totalDurationMs: 1,
      );
      await w.close(footer);
      await w.close(footer);

      expect(sink.closeCount, 1);
      final footerLines = sink.lines
          .where((l) => (jsonDecode(l) as Map)['type'] == 'footer')
          .toList();
      expect(footerLines.length, 1);
    });

    test('write after close throws StateError', () async {
      final sink = _RecordingSink();
      final w = TrajectoryWriter(sink);
      await w.writeHeader(_hdr());
      await w.close(const SessionFooter(
        outcome: SessionOutcome.done,
        totalTurns: 0,
        totalDurationMs: 1,
      ));
      expect(() => w.writeTurn(_turn(0)), throwsStateError);
    });

    test('turn before header throws StateError', () async {
      final sink = _RecordingSink();
      final w = TrajectoryWriter(sink);
      expect(() => w.writeTurn(_turn(0)), throwsStateError);
    });

    test('double header throws StateError', () async {
      final sink = _RecordingSink();
      final w = TrajectoryWriter(sink);
      await w.writeHeader(_hdr());
      expect(() => w.writeHeader(_hdr()), throwsStateError);
    });
  });
}
