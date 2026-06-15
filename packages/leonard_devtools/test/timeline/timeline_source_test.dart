import 'dart:async';
import 'dart:convert';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:leonard_devtools/src/timeline/timeline_source.dart';
import 'package:flutter_test/flutter_test.dart';

SessionHeader _hdr() => const SessionHeader(
      goal: 'login',
      agentsMdHash: 'sha256:abc',
      buildIdentifier: 'debug-1.0.0',
      modelIdentifier: 'qwen3.6-35b-a3b@8bit',
      harnessVersion: '0.1.0',
      plugins: [],
      config: {},
    );

TurnRecord _turn(int i) => TurnRecord(
      index: i,
      observation: const {'core': <String, dynamic>{}, 'extensions': <String, dynamic>{}},
      stability: const {},
      proposedAction: const {'tool': 'core.tap'},
      validation: const {'result': 'ok', 'retries': 0},
      executedAction: const {'tool': 'core.tap'},
      diff: const {'core': <String, dynamic>{}, 'extensions': <String, dynamic>{}},
      modelMetadata: const {},
    );

void main() {
  group('LiveTimelineSource', () {
    test('starts empty and appends records as the stream emits', () async {
      final controller = StreamController<TrajectoryRecord>();
      final source = LiveTimelineSource(controller.stream);
      addTearDown(() async {
        await controller.close();
        await source.close();
      });

      expect(source.records.value, isEmpty);

      controller.add(_hdr());
      await Future<void>.delayed(Duration.zero);
      expect(source.records.value.length, 1);
      expect(source.records.value[0], isA<SessionHeader>());

      controller.add(_turn(0));
      await Future<void>.delayed(Duration.zero);
      expect(source.records.value.length, 2);
      expect(source.records.value[1], isA<TurnRecord>());
    });

    test('notifies listeners on each append', () async {
      final controller = StreamController<TrajectoryRecord>();
      final source = LiveTimelineSource(controller.stream);
      addTearDown(() async {
        await controller.close();
        await source.close();
      });

      var notifications = 0;
      source.records.addListener(() => notifications++);
      controller..add(_hdr())..add(_turn(0))..add(_turn(1));
      await Future<void>.delayed(Duration.zero);

      expect(notifications, 3);
    });

    test('close cancels the subscription and is idempotent', () async {
      final controller = StreamController<TrajectoryRecord>();
      final source = LiveTimelineSource(controller.stream);
      controller.add(_hdr());
      await Future<void>.delayed(Duration.zero);

      await source.close();
      await source.close(); // idempotent

      // No further records should be accumulated after close.
      controller.add(_turn(0));
      await Future<void>.delayed(Duration.zero);
      // We can't read source.records.value after close (notifier disposed),
      // so just confirm no exception was thrown above.
      await controller.close();
    });
  });

  group('BrowseTimelineSource', () {
    test('fromJsonl parses all records up front', () {
      final jsonl = [
        jsonEncode(_hdr().toJson()),
        jsonEncode(_turn(0).toJson()),
        jsonEncode(_turn(1).toJson()),
      ].join('\n');

      final source = BrowseTimelineSource.fromJsonl(jsonl);
      addTearDown(source.close);

      expect(source.records.value.length, 3);
      expect(source.records.value[0], isA<SessionHeader>());
      expect(source.records.value[1], isA<TurnRecord>());
    });

    test('fromRecords accepts an in-memory list', () {
      final source = BrowseTimelineSource.fromRecords([_hdr(), _turn(0)]);
      addTearDown(source.close);

      expect(source.records.value.length, 2);
    });
  });
}
