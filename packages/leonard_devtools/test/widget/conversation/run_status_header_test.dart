import 'dart:async';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:leonard_devtools/src/conversation/conversation_state.dart';
import 'package:leonard_devtools/src/conversation/conversation_view_model.dart';
import 'package:leonard_devtools/src/conversation/run_status_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RunStatusHeader', () {
    testWidgets('shows idle when vm is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: RunStatusHeader())),
      );
      expect(find.byKey(const Key('runStatus.idle')), findsOneWidget);
      expect(find.text('Session 0 · idle'), findsOneWidget);
    });

    testWidgets('shows running chip when status is running', (tester) async {
      final events = StreamController<TurnEvent>.broadcast();
      final traj = StreamController<TrajectoryRecord>.broadcast();
      final startedAt = DateTime.utc(2026, 1, 1);
      final vm = ConversationViewModel(
        turnEvents: events.stream,
        trajectory: traj.stream,
        startedAt: startedAt,
      );
      addTearDown(() async {
        vm.dispose();
        await events.close();
        await traj.close();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RunStatusHeader(vm: vm)),
        ),
      );
      expect(find.byKey(const Key('runStatus.running')), findsOneWidget);
      expect(
        find.textContaining('Session 0 · running · Turn 1'),
        findsOneWidget,
      );
    });

    testWidgets('shows done chip after complete(done)', (tester) async {
      final events = StreamController<TurnEvent>.broadcast();
      final traj = StreamController<TrajectoryRecord>.broadcast();
      final vm = ConversationViewModel(
        turnEvents: events.stream,
        trajectory: traj.stream,
        startedAt: DateTime.utc(2026, 1, 1),
      );
      addTearDown(() async {
        vm.dispose();
        await events.close();
        await traj.close();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RunStatusHeader(vm: vm)),
        ),
      );
      vm.complete(RunStatus.done);
      await tester.pump();

      expect(find.byKey(const Key('runStatus.done')), findsOneWidget);
      expect(find.text('Session 0 · done'), findsOneWidget);
    });

    testWidgets('shows error chip after complete(error)', (tester) async {
      final events = StreamController<TurnEvent>.broadcast();
      final traj = StreamController<TrajectoryRecord>.broadcast();
      final vm = ConversationViewModel(
        turnEvents: events.stream,
        trajectory: traj.stream,
        startedAt: DateTime.utc(2026, 1, 1),
      );
      addTearDown(() async {
        vm.dispose();
        await events.close();
        await traj.close();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RunStatusHeader(vm: vm)),
        ),
      );
      vm.complete(RunStatus.error);
      await tester.pump();

      expect(find.byKey(const Key('runStatus.error')), findsOneWidget);
      expect(find.text('Session 0 · error'), findsOneWidget);
    });

    testWidgets('shows the resident generation in terminal status', (
      tester,
    ) async {
      final events = StreamController<TurnEvent>.broadcast();
      final traj = StreamController<TrajectoryRecord>.broadcast();
      final vm = ConversationViewModel(
        turnEvents: events.stream,
        trajectory: traj.stream,
        sessionGeneration: 7,
        startedAt: DateTime.utc(2026, 1, 1),
      );
      addTearDown(() async {
        vm.dispose();
        await events.close();
        await traj.close();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RunStatusHeader(vm: vm)),
        ),
      );
      vm.complete(RunStatus.done);
      await tester.pump();

      expect(find.text('Session 7 · done'), findsOneWidget);
    });
  });
}
