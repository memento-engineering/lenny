@Tags(['perf'])
library;

import 'dart:math' as math;

import 'package:leonard_agent/leonard_agent.dart';
import 'package:leonard_devtools/src/timeline/timeline_panel.dart';
import 'package:leonard_devtools/src/timeline/timeline_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a [TurnRecord] with a realistic ~8KB observation payload.
TurnRecord _syntheticTurn(int i) {
  final nodes = List<Map<String, dynamic>>.generate(40, (n) {
    return {
      'id': 'n_${i}_$n',
      'label': 'Node $n turn $i',
      'rect': [n * 4, n * 8, 120, 40],
      'role': n.isEven ? 'Button' : 'Text',
      'flags': const {'enabled': true, 'visible': true},
    };
  });
  return TurnRecord(
    index: i,
    observation: {
      'core': {
        'route_stack': const ['Home', 'List'],
        'nodes': nodes,
      },
      'extensions': const {
        'router': {'route': '/list'},
      },
    },
    stability: const {'policy': 'action_relative'},
    proposedAction: {'tool': 'core.tap', 'args': {'id': 'item_$i'}},
    validation: const {'result': 'ok', 'retries': 0},
    executedAction: {'tool': 'core.tap', 'args': {'id': 'item_$i'}},
    diff: const {
      'core': {
        'nodes_added': [{'id': 'x'}],
      },
      'extensions': <String, dynamic>{},
    },
    modelMetadata: const {'tokens_in': 32, 'tokens_out': 8},
  );
}

void main() {
  testWidgets(
    'scrolls 6000-turn fixture under perf budget',
    (tester) async {
      // Generate 6000 turns up front (~50MB observation payload total).
      final records = <TrajectoryRecord>[
        for (var i = 0; i < 6000; i++) _syntheticTurn(i),
      ];

      final source = BrowseTimelineSource.fromRecords(records);
      addTearDown(source.close);

      // Mount with a constrained viewport so ListView.builder must
      // virtualize.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 480,
            height: 640,
            child: TimelinePanel(
              source: source,
              onPickJsonl: () async => null,
            ),
          ),
        ),
      ));

      // Initial frame: <500ms budget.
      final initialSw = Stopwatch()..start();
      await tester.pump();
      initialSw.stop();
      expect(
        initialSw.elapsedMilliseconds,
        lessThan(500),
        reason:
            'Initial frame must render in <500ms (was ${initialSw.elapsedMilliseconds}ms).',
      );

      // Sanity: not all 6000 rows are in the tree (virtualized).
      final listView = find.byType(ListView);
      expect(listView, findsOneWidget);

      // Steady-state scroll: drag 30 times and assert the worst single
      // frame stays under 16ms. We measure pump() not drag(), since
      // drag() includes the gesture machinery.
      final frameTimings = <int>[];
      for (var i = 0; i < 30; i++) {
        await tester.drag(listView, const Offset(0, -300));
        final sw = Stopwatch()..start();
        await tester.pump();
        sw.stop();
        frameTimings.add(sw.elapsedMicroseconds);
      }

      final worstUs = frameTimings.reduce(math.max);
      expect(
        worstUs,
        lessThan(16000),
        reason: 'Worst-frame budget exceeded: ${worstUs}us > 16000us. '
            'Timings: $frameTimings',
      );
    },
    // Tag-gated: run with `flutter test --tags perf`.
  );
}
