import 'dart:convert';

import 'package:exploration_agent/exploration_agent.dart';
import 'package:exploration_devtools/src/broadcast_trajectory_sink.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('writeLine emits a parsed TrajectoryRecord on records stream',
      () async {
    final sink = BroadcastTrajectorySink();
    final emitted = <TrajectoryRecord>[];
    final sub = sink.records.listen(emitted.add);

    const header = SessionHeader(
      goal: 'g',
      agentsMdHash: '',
      buildIdentifier: 'devtools',
      modelIdentifier: 'm',
      harnessVersion: 'v',
      plugins: <PluginManifestRecord>[],
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

  test('integrates with TrajectoryWriter: header + turn fan out',
      () async {
    final sink = BroadcastTrajectorySink();
    final writer = TrajectoryWriter(sink);
    final emitted = <TrajectoryRecord>[];
    final sub = sink.records.listen(emitted.add);

    await writer.writeHeader(const SessionHeader(
      goal: 'g',
      agentsMdHash: '',
      buildIdentifier: 'devtools',
      modelIdentifier: 'm',
      harnessVersion: 'v',
      plugins: <PluginManifestRecord>[],
      config: <String, dynamic>{},
    ));
    await writer.writeTurn(const TurnRecord(
      index: 0,
      observation: <String, dynamic>{},
      stability: <String, dynamic>{},
      proposedAction: <String, dynamic>{},
      validation: <String, dynamic>{},
      executedAction: <String, dynamic>{},
      diff: <String, dynamic>{},
      summaryUpdate: '',
      modelMetadata: <String, dynamic>{},
    ));
    await Future<void>.delayed(Duration.zero);

    expect(emitted, hasLength(2));
    expect(emitted[0], isA<SessionHeader>());
    expect(emitted[1], isA<TurnRecord>());

    await sub.cancel();
    await writer.close(const SessionFooter(
      outcome: SessionOutcome.done,
      finalSummary: '',
      totalTurns: 1,
      totalDurationMs: 0,
    ));
  });
}
