import 'package:leonard_agent/leonard_agent.dart';
import 'package:leonard_devtools/src/timeline/turn_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TurnRecord _turn({
  int index = 0,
  Map<String, dynamic> executedAction = const {'tool': 'core.tap', 'args': <String, dynamic>{}},
  Map<String, dynamic> diff = const {'core': <String, dynamic>{}, 'extensions': <String, dynamic>{}},
  String? thinking,
}) =>
    TurnRecord(
      index: index,
      observation: const {'core': <String, dynamic>{}, 'extensions': <String, dynamic>{}},
      stability: const {},
      proposedAction: executedAction,
      validation: const {'result': 'ok', 'retries': 0},
      executedAction: executedAction,
      diff: diff,
      thinking: thinking,
      modelMetadata: const {},
    );

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 320, child: child),
      ),
    );

void main() {
  group('TurnRow.describeAction', () {
    test('emits #idx tool(args) format', () {
      expect(
        TurnRow.describeAction(
          const {'tool': 'router.go', 'args': {'route': '/login'}},
          index: 4,
        ),
        '#4 router.go(route=/login)',
      );
    });

    test('takes only the first three args', () {
      expect(
        TurnRow.describeAction(
          const {
            'tool': 'core.tap',
            'args': {'a': 1, 'b': 2, 'c': 3, 'd': 4},
          },
          index: 0,
        ),
        '#0 core.tap(a=1, b=2, c=3)',
      );
    });

    test('handles missing args map', () {
      expect(
        TurnRow.describeAction(const {'tool': 'core.tap'}, index: 1),
        '#1 core.tap()',
      );
    });
  });

  group('TurnRow.describeDiff', () {
    test('summarises core node deltas and route change', () {
      final summary = TurnRow.describeDiff(const {
        'core': {
          'nodes_added': [
            {'id': 1},
            {'id': 2},
          ],
          'nodes_removed': [
            {'id': 3},
          ],
          'route_changes': [
            {
              'current': ['Home', 'Login'],
            },
          ],
        },
        'extensions': <String, dynamic>{},
      });
      expect(summary, '+2 nodes, -1 nodes, route -> Home/Login');
    });

    test('large node delta produces a single short string (no inline JSON)', () {
      final added = List<Map<String, dynamic>>.generate(
        100,
        (i) => {'id': i},
      );
      final summary = TurnRow.describeDiff({
        'core': {'nodes_added': added},
        'extensions': <String, dynamic>{},
      });
      expect(summary, '+100 nodes');
      expect(summary.length, lessThan(40));
    });

    test('plugin fragments surface as namespace: changed', () {
      final summary = TurnRow.describeDiff(const {
        'core': <String, dynamic>{},
        'extensions': {
          'router': {'route_changes': <Object?>[]},
          'dio': {'requests': <Object?>[]},
        },
      });
      expect(summary, contains('router: changed'));
      expect(summary, contains('dio: changed'));
    });

    test('empty diff yields (no changes)', () {
      expect(
        TurnRow.describeDiff(const {
          'core': <String, dynamic>{},
          'extensions': <String, dynamic>{},
        }),
        '(no changes)',
      );
    });
  });

  group('TurnRow widget', () {
    testWidgets('three-line layout golden — action, diff, summary', (tester) async {
      var tapped = 0;
      final record = _turn(
        index: 7,
        executedAction: const {'tool': 'core.tap', 'args': {'id': 'submit'}},
        diff: const {
          'core': {
            'nodes_added': [
              {'id': 1},
            ],
          },
          'extensions': <String, dynamic>{},
        },
        thinking: 'submitted login form',
      );
      await tester.pumpWidget(_wrap(TurnRow(
        record: record,
        onTap: () => tapped++,
      )));

      expect(find.text('#7 core.tap(id=submit)'), findsOneWidget);
      expect(find.text('+1 nodes'), findsOneWidget);
      expect(find.text('submitted login form'), findsOneWidget);

      await tester.tap(find.byType(InkWell));
      expect(tapped, 1);
    });

    testWidgets('100-node delta truncates to one line', (tester) async {
      final added = List<Map<String, dynamic>>.generate(100, (i) => {'id': i});
      final record = _turn(diff: {
        'core': {'nodes_added': added},
        'extensions': <String, dynamic>{},
      });
      await tester.pumpWidget(_wrap(TurnRow(record: record, onTap: () {})));

      // The diff line should render without overflow because the
      // describeDiff helper compresses the list to a count.
      final diffText = tester.widget<Text>(find.text('+100 nodes'));
      expect(diffText.maxLines, 1);
      expect(diffText.overflow, TextOverflow.ellipsis);
    });
  });

  group('ExtensionDisabledRow widget', () {
    testWidgets('plugin-disabled variant renders namespace + reason', (tester) async {
      await tester.pumpWidget(_wrap(const ExtensionDisabledRow(
        record: ExtensionDisabledEvent(
          namespace: 'dio',
          reason: 'auto_disabled_after_3_failures',
          turn: 4,
        ),
      )));
      expect(
        find.textContaining('plugin disabled (turn 4): dio'),
        findsOneWidget,
      );
      expect(find.textContaining('auto_disabled_after_3_failures'),
          findsOneWidget);
    });
  });

  group('UnknownRecordRow widget', () {
    testWidgets('renders unknown record type warning', (tester) async {
      await tester.pumpWidget(_wrap(const UnknownRecordRow(
        record: UnknownTrajectoryRecord(rawType: 'flux_capacitor', raw: {}),
      )));
      expect(
        find.text('unknown record type: flux_capacitor'),
        findsOneWidget,
      );
    });
  });
}
