import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/gauntlet/scenario_oracle.dart';
import 'package:sample_app/gauntlet/scenarios/async_reveal_screen.dart';
import 'package:sample_app/gauntlet/scenarios/debounced_search_screen.dart';
import 'package:sample_app/gauntlet/scenarios/optimistic_revert_screen.dart';
import 'package:sample_app/gauntlet/scenarios/staggered_list_screen.dart';
import 'package:sample_app/gauntlet/scenarios/transient_toast_screen.dart';

Widget _host(Widget screen) => ProviderScope(child: MaterialApp(home: screen));

void main() {
  tearDown(() => gauntletOracle.value = null);

  testWidgets('async-reveal: code appears only after the dio round-trip', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(const AsyncRevealScreen()));
    await tester.pump();
    // Look early — still loading, no code.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('AZ-4471'), findsNothing);

    // 250ms base + 1300ms scenario latency.
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    expect(find.text('AZ-4471'), findsOneWidget);
    expect(gauntletOracle.value?.expected['code'], 'AZ-4471');
  });

  testWidgets('optimistic-revert: flashes liked, settles unliked', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(const OptimisticRevertScreen()));
    await tester.pump();
    expect(find.text('Liked: no'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump(); // optimistic flash
    expect(find.text('Liked: yes'), findsOneWidget);

    // 250ms + 550ms reconcile -> server reverts to not-liked.
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Liked: no'), findsOneWidget);
    expect(gauntletOracle.value?.expected['settled_liked'], false);
  });

  testWidgets('debounced-search: results arrive after debounce + fetch', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(const DebouncedSearchScreen()));
    await tester.enterText(find.byType(TextField), 'widget');

    // Before the debounce fires, no results yet.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('5 result(s)'), findsNothing);

    // 300ms debounce + 250ms base + 350ms scenario latency.
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump();
    expect(find.text('5 result(s)'), findsOneWidget);
    expect(gauntletOracle.value?.expected['count'], 5);
  });

  testWidgets('staggered-list: settles at 20 after the entrance', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(const StaggeredListScreen()));
    await tester.pump();
    expect(gauntletOracle.value?.scenarioId, 'settle/staggered-list');

    // 20 items * 50ms + tween. Let the entrance finish.
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('Row 1'), findsOneWidget);
    expect(gauntletOracle.value?.expected['count'], 20);
  });

  testWidgets('transient-toast: message shows in-window, then dismisses', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(const TransientToastScreen()));
    await tester.tap(find.text('Submit'));
    await tester.pump();
    // Before 500ms — not shown yet.
    expect(find.text('Saved as draft #7'), findsNothing);

    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Saved as draft #7'), findsOneWidget);
    expect(gauntletOracle.value?.goalReached, isTrue);

    // Let the entrance finish first (the 2500ms display timer only starts
    // once the snackbar is fully shown), then wait it out and flush the
    // exit transition before asserting it's gone.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pumpAndSettle();
    expect(find.text('Saved as draft #7'), findsNothing);
  });
}
