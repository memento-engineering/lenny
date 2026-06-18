import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/gauntlet/scenario_oracle.dart';
import 'package:sample_app/gauntlet/scenarios/custom_paint_control_screen.dart';
import 'package:sample_app/gauntlet/scenarios/expand_to_reach_screen.dart';
import 'package:sample_app/gauntlet/scenarios/label_lie_screen.dart';
import 'package:sample_app/gauntlet/scenarios/lazy_offscreen_screen.dart';
import 'package:sample_app/gauntlet/scenarios/modal_trap_screen.dart';
import 'package:sample_app/gauntlet/scenarios/slider_semantic_value_screen.dart';

Widget _host(Widget screen) => MaterialApp(home: screen);

void main() {
  tearDown(() => gauntletOracle.value = null);

  testWidgets('label-lie: tapping the semantic-"Submit" button wins', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(const LabelLieScreen()));
    // The semantic "Submit" is the button that READS "Continue".
    await tester.tap(find.bySemanticsLabel('Submit'));
    await tester.pump();
    expect(gauntletOracle.value?.goalReached, isTrue);
    handle.dispose();
  });

  testWidgets('slider-semantic-value: 7 is the ground truth, not on screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(const SliderSemanticValueScreen()));
    await tester.pump();

    expect(gauntletOracle.value?.expected['value'], 7);
    // The value is never shown as visible text — it lives only in the
    // slider's semantic value (validated under live-drive).
    expect(find.text('7'), findsNothing);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('expand-to-reach: switch only reachable after expanding', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(const ExpandToReachScreen()));
    // Collapsed: the switch isn't in the tree.
    expect(find.byType(Switch), findsNothing);

    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(gauntletOracle.value?.goalReached, isTrue);
  });

  testWidgets('modal-trap: Settings only reachable after dismissing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(const ModalTrapScreen()));
    await tester.pumpAndSettle(); // dialog shows
    expect(find.text('Notice'), findsOneWidget);

    // Tapping Settings while the barrier is up does nothing.
    await tester.tap(find.text('Open Settings'), warnIfMissed: false);
    await tester.pump();
    expect(gauntletOracle.value?.goalReached, isFalse);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle(); // dialog dismisses
    await tester.tap(find.text('Open Settings'));
    await tester.pump();
    expect(gauntletOracle.value?.goalReached, isTrue);
  });

  testWidgets('lazy-offscreen: row 150 materialises only after scrolling', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(const LazyOffscreenScreen()));
    expect(find.text('Row 150'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Row 150'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Row 150'));
    await tester.pump();
    expect(gauntletOracle.value?.goalReached, isTrue);
  });

  testWidgets('custom-paint-control: selecting segment B flips the oracle', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(const CustomPaintControlScreen()));
    await tester.tap(find.bySemanticsLabel('Segment B'));
    await tester.pump();
    expect(gauntletOracle.value?.goalReached, isTrue);
    handle.dispose();
  });
}
