import 'dart:convert';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:leonard_devtools/src/broadcast_trajectory_sink.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('writeLine emits a parsed TrajectoryRecord on records stream', () async {
    final sink = BroadcastTrajectorySink();
    final emitted = <TrajectoryRecord>[];
    final sub = sink.records.listen(emitted.add);

    const header = SessionHeader(
      goal: 'g',
      agentsMdHash: '',
      buildIdentifier: 'devtools',
      modelIdentifier: 'm',
      harnessVersion: 'v',
      extensions: <ExtensionManifestRecord>[],
      config: <String, dynamic>{},
    );
    await sink.writeLine(jsonEncode(header.toJson()));
    await Future<void>.delayed(Duration.zero);

    expect(emitted, hasLength(1));
    expect(emitted.single, isA<SessionHeader>());

    await sub.cancel();
    await sink.close();
  });

  test('close is idempotent and rejects further writes', () async {
    final sink = BroadcastTrajectorySink();
    await sink.close();
    await sink.close();

    expect(() => sink.writeLine('{}'), throwsA(isA<StateError>()));
  });

  test('flush is a no-op (in-memory sink)', () async {
    final sink = BroadcastTrajectorySink();
    await sink.flush();
    await sink.close();
  });

  test('integrates with TrajectoryWriter: header + turn fan out', () async {
    final sink = BroadcastTrajectorySink();
    final writer = TrajectoryWriter(sink);
    final emitted = <TrajectoryRecord>[];
    final sub = sink.records.listen(emitted.add);

    await writer.writeHeader(
      const SessionHeader(
        goal: 'g',
        agentsMdHash: '',
        buildIdentifier: 'devtools',
        modelIdentifier: 'm',
        harnessVersion: 'v',
        extensions: <ExtensionManifestRecord>[],
        config: <String, dynamic>{},
      ),
    );
    await writer.writeTurn(
      const TurnRecord(
        index: 0,
        observation: <String, dynamic>{},
        stability: <String, dynamic>{},
        proposedAction: <String, dynamic>{},
        validation: <String, dynamic>{},
        executedAction: <String, dynamic>{},
        diff: <String, dynamic>{},
        modelMetadata: <String, dynamic>{},
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(emitted, hasLength(2));
    expect(emitted[0], isA<SessionHeader>());
    expect(emitted[1], isA<TurnRecord>());

    await sub.cancel();
    await writer.close(
      const SessionFooter(
        outcome: SessionOutcome.done,
        totalTurns: 1,
        totalDurationMs: 0,
      ),
    );
  });

  test(
    'a late listener receives the session so far, then live records',
    () async {
      final sink = BroadcastTrajectorySink();
      SessionHeader header(String goal) => SessionHeader(
        goal: goal,
        agentsMdHash: '',
        buildIdentifier: 'devtools',
        modelIdentifier: 'm',
        harnessVersion: 'v',
        extensions: const <ExtensionManifestRecord>[],
        config: const <String, dynamic>{},
      );
      await sink.writeLine(jsonEncode(header('first').toJson()));
      await sink.writeLine(jsonEncode(header('second').toJson()));

      final late = <String>[];
      final sub = sink.records.listen(
        (TrajectoryRecord r) => late.add((r as SessionHeader).goal),
      );
      await Future<void>.delayed(Duration.zero);
      expect(late, <String>['first', 'second']);

      await sink.writeLine(jsonEncode(header('third').toJson()));
      await Future<void>.delayed(Duration.zero);
      expect(late, <String>['first', 'second', 'third']);

      final second = <String>[];
      final sub2 = sink.records.listen(
        (TrajectoryRecord r) => second.add((r as SessionHeader).goal),
      );
      await Future<void>.delayed(Duration.zero);
      expect(second, <String>['first', 'second', 'third']);

      await sub.cancel();
      await sub2.cancel();
      await sink.close();
    },
  );
}
