import 'dart:async';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:leonard_devtools/src/conversation/conversation_view_model.dart';
import 'package:leonard_devtools/src/conversation/transcript_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TranscriptList', () {
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

    testWidgets('shows empty-state text before any turns', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TranscriptList(viewModel: vm)),
      ));
      await tester.pump();
      expect(find.byKey(const Key('transcript.empty')), findsOneWidget);
    });

    testWidgets('renders entry when a turn is added', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TranscriptList(viewModel: vm)),
      ));

      events.add(const TurnThinking(0, ThinkingDelta(text: 'hi', isFinal: false)));
      // Two pumps: first delivers stream microtasks + rebuilds; second runs
      // the post-frame auto-scroll callback registered by _onStateChanged.
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('transcript.list')), findsOneWidget);
      expect(find.byKey(const ValueKey('entry.0')), findsOneWidget);
    });
  });
}
