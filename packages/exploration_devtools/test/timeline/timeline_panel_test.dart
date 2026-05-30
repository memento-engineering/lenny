import 'dart:async';
import 'dart:convert';

import 'package:exploration_agent/exploration_agent.dart';
import 'package:exploration_devtools/src/exploration_shell.dart';
import 'package:exploration_devtools/src/timeline/timeline_panel.dart';
import 'package:exploration_devtools/src/timeline/timeline_source.dart';
import 'package:exploration_devtools/src/timeline/turn_row.dart';
import 'package:flutter/material.dart';
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
      observation: const {'core': <String, dynamic>{}, 'plugins': <String, dynamic>{}},
      stability: const {},
      proposedAction: const {'tool': 'core.tap'},
      validation: const {'result': 'ok', 'retries': 0},
      executedAction: {'tool': 'core.tap', 'args': {'i': '$i'}},
      diff: const {'core': <String, dynamic>{}, 'plugins': <String, dynamic>{}},
      modelMetadata: const {},
    );

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 480, height: 600, child: child)),
    );

void main() {
  group('TimelinePanel', () {
    testWidgets('mounts under Timeline tab', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ExplorationShell(
          manifestProbe: () async => const [],
          sessionFactory: () async => throw StateError('no session'),
        ),
      ));
      // Default selected tab is Prompt; switch to Timeline.
      await tester.tap(find.text('Timeline'));
      await tester.pumpAndSettle();
      // The placeholder text from .21 must be gone, and the Browse button
      // from TimelinePanel must be present.
      expect(find.textContaining('lenny-cx6.24'), findsNothing);
      expect(find.text('Browse JSONL'), findsOneWidget);
      expect(find.text('Live'), findsOneWidget);
    });

    testWidgets('renders empty state in live mode', (tester) async {
      final source = LiveTimelineSource(const Stream.empty());
      addTearDown(source.close);
      await tester.pumpWidget(_wrap(TimelinePanel(
        source: source,
        onPickJsonl: () async => null,
      )));
      await tester.pumpAndSettle();
      expect(find.text('Waiting for trajectory records...'), findsOneWidget);
    });

    testWidgets('appends without rebuilding existing rows (1000 turns)',
        (tester) async {
      final controller = StreamController<TrajectoryRecord>();
      addTearDown(controller.close);
      final source = LiveTimelineSource(controller.stream);
      addTearDown(source.close);

      await tester.pumpWidget(_wrap(TimelinePanel(
        source: source,
        onPickJsonl: () async => null,
      )));
      await tester.pumpAndSettle();

      // Push a header + first 5 turns and capture row Element identity.
      controller.add(_hdr());
      for (var i = 0; i < 5; i++) {
        controller.add(_turn(i));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      // Capture identity of an early-row element.
      final earlyKey = const ValueKey<String>('turn-0');
      final earlyElementBefore = tester.element(find.byKey(earlyKey));

      // Now pump 995 more so the list reaches 1000 turns.
      for (var i = 5; i < 1000; i++) {
        controller.add(_turn(i));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      // The early row's Element identity must be unchanged: ListView.builder
      // recycles slots but stable ValueKeys preserve the State/Element.
      final earlyElementAfter = tester.element(find.byKey(earlyKey));
      expect(identical(earlyElementBefore, earlyElementAfter), isTrue,
          reason: 'Existing rows must not be rebuilt when new records append.');

      // Sanity: TurnRow widgets exist and are virtualized (not 1000 in tree).
      final turnRows = find.byType(TurnRow);
      expect(turnRows.evaluate().length, lessThan(50),
          reason: 'ListView.builder should virtualize off-screen rows.');
    });

    testWidgets('plugin-disabled and unknown records render distinct row variants',
        (tester) async {
      final source = BrowseTimelineSource.fromRecords([
        _hdr(),
        _turn(0),
        const PluginDisabledEvent(
          namespace: 'dio',
          reason: 'auto_disabled',
          turn: 1,
        ),
        const UnknownTrajectoryRecord(rawType: 'flux', raw: {'a': 1}),
      ]);
      addTearDown(source.close);

      await tester.pumpWidget(_wrap(TimelinePanel(
        source: source,
        onPickJsonl: () async => null,
      )));
      await tester.pumpAndSettle();

      expect(find.byType(PluginDisabledRow), findsOneWidget);
      expect(find.byType(UnknownRecordRow), findsOneWidget);
      expect(find.byType(TurnRow), findsOneWidget);
    });

    testWidgets('browse mode loads JSONL via picker and renders rows',
        (tester) async {
      final liveSource = LiveTimelineSource(const Stream.empty());
      addTearDown(liveSource.close);

      final jsonl = [
        jsonEncode(_hdr().toJson()),
        jsonEncode(_turn(0).toJson()),
        jsonEncode(_turn(1).toJson()),
      ].join('\n');

      var pickCalls = 0;
      Future<String?> picker() async {
        pickCalls++;
        return jsonl;
      }

      await tester.pumpWidget(_wrap(TimelinePanel(
        source: liveSource,
        onPickJsonl: picker,
      )));
      await tester.pumpAndSettle();

      // Initially live + empty.
      expect(find.text('Waiting for trajectory records...'), findsOneWidget);

      // Tap Browse, which calls the picker and loads records.
      await tester.tap(find.text('Browse JSONL'));
      await tester.pumpAndSettle();

      expect(pickCalls, 1);
      expect(find.byType(TurnRow), findsNWidgets(2));
      expect(find.text('Waiting for trajectory records...'), findsNothing);
    });

    testWidgets('Live button returns to live source after browsing',
        (tester) async {
      final controller = StreamController<TrajectoryRecord>();
      addTearDown(controller.close);
      final liveSource = LiveTimelineSource(controller.stream);
      addTearDown(liveSource.close);

      final jsonl = [
        jsonEncode(_hdr().toJson()),
        jsonEncode(_turn(0).toJson()),
      ].join('\n');

      await tester.pumpWidget(_wrap(TimelinePanel(
        source: liveSource,
        onPickJsonl: () async => jsonl,
      )));
      controller.add(_hdr());
      controller.add(_turn(99));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      // Live mode shows turn 99.
      expect(find.text('#99 core.tap(i=99)'), findsOneWidget);

      await tester.tap(find.text('Browse JSONL'));
      await tester.pumpAndSettle();
      // Browse mode swaps in fixture rows: turn 0 only.
      expect(find.text('#99 core.tap(i=99)'), findsNothing);
      expect(find.text('#0 core.tap(i=0)'), findsOneWidget);

      await tester.tap(find.text('Live'));
      await tester.pumpAndSettle();
      // Back to live, turn 99 visible again.
      expect(find.text('#99 core.tap(i=99)'), findsOneWidget);
    });

    testWidgets('tapping a TurnRow pushes TurnDetailView', (tester) async {
      final source = BrowseTimelineSource.fromRecords([_hdr(), _turn(0)]);
      addTearDown(source.close);

      await tester.pumpWidget(_wrap(TimelinePanel(
        source: source,
        onPickJsonl: () async => null,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TurnRow));
      await tester.pumpAndSettle();

      expect(find.text('Turn #0'), findsOneWidget);
    });
  });
}
