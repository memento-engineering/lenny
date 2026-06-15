import 'dart:async';
import 'dart:convert';

import 'package:leonard_agent/src/trajectory/reader.dart';
import 'package:leonard_agent/src/trajectory/records.dart';
import 'package:leonard_agent/src/trajectory/writer.dart';
import 'package:leonard_agent/src/trajectory/sink.dart';
import 'package:test/test.dart';

class _RecordingSink implements TrajectorySink {
  final List<String> lines = [];
  @override
  Future<void> writeLine(String line) async {
    lines.add(line);
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
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
  observation: const {
    'core': <String, dynamic>{},
    'extensions': <String, dynamic>{},
  },
  stability: const {'policy': 'action_relative'},
  proposedAction: const {'tool': 'core.tap'},
  validation: const {'result': 'ok', 'retries': 0},
  executedAction: const {'tool': 'core.tap'},
  diff: const {'core': <String, dynamic>{}, 'extensions': <String, dynamic>{}},
  modelMetadata: const {'tokens_in': 10, 'tokens_out': 5, 'duration_ms': 200},
);

void main() {
  group('TrajectoryReader.readAll', () {
    test(
      'round-trips a 4-record fixture written by TrajectoryWriter',
      () async {
        final sink = _RecordingSink();
        final w = TrajectoryWriter(sink);
        await w.writeHeader(_hdr());
        await w.writeTurn(_turn(0));
        await w.writeExtensionDisabled(
          const ExtensionDisabledEvent(
            namespace: 'dio',
            reason: 'auto_disabled_after_3_failures',
            turn: 1,
          ),
        );
        await w.close(
          const SessionFooter(
            outcome: SessionOutcome.done,
            totalTurns: 1,
            totalDurationMs: 1234,
          ),
        );

        // Reconstruct the JSONL the writer would have produced (the recording
        // sink stores raw lines without trailing newlines).
        final jsonl = sink.lines.join('\n');
        final records = TrajectoryReader.readAll(jsonl);

        expect(records.length, 4);
        expect(records[0], isA<SessionHeader>());
        final header = records[0] as SessionHeader;
        expect(header.goal, 'login');
        expect(header.plugins.single.namespace, 'router');

        expect(records[1], isA<TurnRecord>());
        final turn = records[1] as TurnRecord;
        expect(turn.index, 0);
        expect(turn.thinking, isNull);
        expect(turn.executedAction['tool'], 'core.tap');

        expect(records[2], isA<ExtensionDisabledEvent>());
        final disabled = records[2] as ExtensionDisabledEvent;
        expect(disabled.namespace, 'dio');
        expect(disabled.turn, 1);

        expect(records[3], isA<SessionFooter>());
        final footer = records[3] as SessionFooter;
        expect(footer.outcome, SessionOutcome.done);
        expect(footer.totalTurns, 1);
      },
    );

    test('skips empty lines (e.g. trailing newline)', () {
      final jsonl = '${jsonEncode(_hdr().toJson())}\n\n';
      final records = TrajectoryReader.readAll(jsonl);
      expect(records.length, 1);
      expect(records.single, isA<SessionHeader>());
    });

    test('unknown type yields UnknownTrajectoryRecord without throwing', () {
      final jsonl = [
        jsonEncode(_hdr().toJson()),
        jsonEncode({'type': 'flux_capacitor', 'energy': 1.21}),
        jsonEncode(_turn(7).toJson()),
      ].join('\n');

      final records = TrajectoryReader.readAll(jsonl);
      expect(records.length, 3);
      expect(records[1], isA<UnknownTrajectoryRecord>());
      final unknown = records[1] as UnknownTrajectoryRecord;
      expect(unknown.rawType, 'flux_capacitor');
      expect(unknown.raw['energy'], 1.21);
      expect(records[2], isA<TurnRecord>());
    });

    test(
      'missing type discriminator yields UnknownTrajectoryRecord(rawType: "null")',
      () {
        final jsonl = jsonEncode({'index': 0});
        final records = TrajectoryReader.readAll(jsonl);
        final unknown = records.single as UnknownTrajectoryRecord;
        expect(unknown.rawType, 'null');
      },
    );
  });

  group('TrajectoryReader.readStream', () {
    test('emits records lazily from a line stream', () async {
      final lines = Stream<String>.fromIterable([
        jsonEncode(_hdr().toJson()),
        '',
        jsonEncode(_turn(0).toJson()),
      ]);
      final records = await TrajectoryReader.readStream(lines).toList();
      expect(records.length, 2);
      expect(records[0], isA<SessionHeader>());
      expect(records[1], isA<TurnRecord>());
    });
  });
}
