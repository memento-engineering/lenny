import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/gauntlet/scenario_oracle.dart';
import 'package:sample_app/gauntlet/scenarios/decorative_motion_screen.dart';

void main() {
  tearDown(() => gauntletOracle.value = null);

  testWidgets('mount activates the oracle; tapping ready flips goal_reached', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: DecorativeMotionScreen()));

    // NOTE: never pumpAndSettle() here — the shimmer/pulse run on a
    // perpetual repeat() controller, so the tree never reaches a steady
    // state and pumpAndSettle would time out. Advancing by fixed durations
    // is exactly how a settle-aware agent has to treat this screen.
    await tester.pump(const Duration(milliseconds: 100));

    final ScenarioOracleState? active = gauntletOracle.value;
    expect(active?.scenarioId, 'settle/decorative-motion');
    expect(active?.expected, <String, Object?>{'action': 'tap_ready'});
    expect(active?.goalReached, isFalse);

    await tester.tap(find.text("I'm ready"));
    await tester.pump(const Duration(milliseconds: 100));

    expect(gauntletOracle.value?.goalReached, isTrue);
  });

  testWidgets('unmount clears the active oracle', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: DecorativeMotionScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(gauntletOracle.value, isNotNull);

    // Replace the tree -> the scenario disposes -> oracle deactivates.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(gauntletOracle.value, isNull);
  });
}
