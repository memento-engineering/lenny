import 'dart:async';

import 'package:exploration_agent/exploration_agent.dart';
import 'package:exploration_devtools/src/conversation/conversation_state.dart';
import 'package:exploration_devtools/src/conversation/conversation_view_model.dart';
import 'package:test/test.dart';

void main() {
  group('ConversationViewModel', () {
    late StreamController<TurnEvent> events;
    late StreamController<TrajectoryRecord> trajectory;
    late ConversationViewModel vm;

    setUp(() {
      events = StreamController<TurnEvent>.broadcast();
      trajectory = StreamController<TrajectoryRecord>.broadcast();
      vm = ConversationViewModel(
        turnEvents: events.stream,
        trajectory: trajectory.stream,
      );
    });

    tearDown(() async {
      vm.dispose();
      await events.close();
      await trajectory.close();
    });

    test('initial state is running with no entries', () {
      expect(vm.value.status, RunStatus.running);
      expect(vm.value.entries, isEmpty);
      expect(vm.value.currentTurn, -1);
    });

    test('initial state has startedAt set', () {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final after = DateTime.now().add(const Duration(seconds: 1));
      expect(vm.value.startedAt, isNotNull);
      expect(vm.value.startedAt!.isAfter(before), isTrue);
      expect(vm.value.startedAt!.isBefore(after), isTrue);
    });

    test('accepts injected startedAt for deterministic tests', () {
      final t = DateTime.utc(2026, 6, 1);
      final events2 = StreamController<TurnEvent>.broadcast();
      final traj2 = StreamController<TrajectoryRecord>.broadcast();
      final vm2 = ConversationViewModel(
        turnEvents: events2.stream,
        trajectory: traj2.stream,
        startedAt: t,
      );
      addTearDown(() async {
        vm2.dispose();
        await events2.close();
        await traj2.close();
      });
      expect(vm2.value.startedAt, t);
    });

    test('TurnThinking creates entry and updates AppendOnlyTextController',
        () async {
      events.add(const TurnThinking(0, ThinkingDelta(text: 'hello ', isFinal: false)));
      events.add(const TurnThinking(0, ThinkingDelta(text: 'world', isFinal: false)));
      await Future<void>.delayed(Duration.zero);

      expect(vm.value.entries, hasLength(1));
      expect(vm.value.entries.first.turnIndex, 0);
      expect(vm.value.currentTurn, 0);
      final ctl = vm.thinkingControllerForTurn(0);
      expect(ctl, isNotNull);
      expect(ctl!.text, 'hello world');
    });

    test('TurnActionDecided populates toolName + toolArgs', () async {
      events.add(const TurnThinking(0, ThinkingDelta(text: 'x', isFinal: false)));
      events.add(const TurnActionDecided(0, 'core.tap', {'element': 'btn'}));
      await Future<void>.delayed(Duration.zero);

      expect(vm.value.entries.first.toolName, 'core.tap');
      expect(vm.value.entries.first.toolArgs, {'element': 'btn'});
    });

    test('TurnRecord completes entry with result (two-phase keying)', () async {
      events.add(const TurnThinking(0, ThinkingDelta(text: 'x', isFinal: false)));
      events.add(const TurnActionDecided(0, 'core.tap', {}));
      trajectory.add(TurnRecord(
        index: 0,
        observation: const {},
        stability: const {},
        proposedAction: const {},
        validation: const {},
        executedAction: const {
          'tool': 'core.tap',
          'args': <String, dynamic>{},
          'result': <String, dynamic>{'ok': true},
        },
        diff: const {},
        modelMetadata: const {},
      ));
      await Future<void>.delayed(Duration.zero);

      expect(vm.value.entries.first.complete, isTrue);
      expect(vm.value.entries.first.toolResult, '✓ ok');
    });

    test(
        'TurnRecord does not duplicate entry when trajectory races ahead of events',
        () async {
      trajectory.add(TurnRecord(
        index: 0,
        observation: const {},
        stability: const {},
        proposedAction: const {},
        validation: const {},
        executedAction: const {
          'tool': 'core.tap',
          'args': <String, dynamic>{},
          'result': <String, dynamic>{'ok': true},
        },
        diff: const {},
        modelMetadata: const {},
      ));
      await Future<void>.delayed(Duration.zero);

      expect(vm.value.entries, hasLength(1));
      expect(vm.value.entries.first.complete, isTrue);

      // Now the thinking event arrives (late)
      events.add(const TurnThinking(0, ThinkingDelta(text: 'late thinking', isFinal: false)));
      await Future<void>.delayed(Duration.zero);

      // Should update the existing entry, NOT add a second one
      expect(vm.value.entries, hasLength(1));
    });

    test('complete() transitions status and freezes further updates', () async {
      events.add(const TurnThinking(0, ThinkingDelta(text: 'x', isFinal: false)));
      await Future<void>.delayed(Duration.zero);

      vm.complete(RunStatus.done);
      expect(vm.value.status, RunStatus.done);

      // Events after complete() are ignored
      events.add(const TurnActionDecided(0, 'core.tap', {}));
      await Future<void>.delayed(Duration.zero);
      expect(vm.value.entries.first.toolName, isNull);
    });
  });
}
