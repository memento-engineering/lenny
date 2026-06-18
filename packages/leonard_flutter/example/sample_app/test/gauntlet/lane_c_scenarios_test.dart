import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/gauntlet/scenario_oracle.dart';
import 'package:sample_app/gauntlet/scenarios/chart_read_screen.dart';
import 'package:sample_app/gauntlet/scenarios/count_spatial_screen.dart';
import 'package:sample_app/gauntlet/scenarios/object_id_screen.dart';
import 'package:sample_app/gauntlet/scenarios/ocr_price_screen.dart';
import 'package:sample_app/gauntlet/scenarios/semantics_lie_screen.dart';

Widget _host(Widget screen) => MaterialApp(home: screen);

void main() {
  tearDown(() => gauntletOracle.value = null);

  group('object-id (bbox tap oracle)', () {
    testWidgets('tap inside the red umbrella flips goal_reached', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(const ObjectIdScreen()));
      final Offset tl = tester.getTopLeft(find.byKey(ObjectIdScreen.sceneKey));
      // Red umbrella center ≈ (0.78, 0.45) of a 320×260 scene.
      await tester.tapAt(tl + const Offset(0.78 * 320, 0.45 * 260));
      await tester.pump();

      expect(gauntletOracle.value?.goalReached, isTrue);
      expect(gauntletOracle.value?.lastTapFraction, isNotNull);
    });

    testWidgets('tap on a different umbrella does NOT flip goal_reached', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(const ObjectIdScreen()));
      final Offset tl = tester.getTopLeft(find.byKey(ObjectIdScreen.sceneKey));
      // Blue umbrella ≈ (0.24, 0.45) — outside the red box.
      await tester.tapAt(tl + const Offset(0.24 * 320, 0.45 * 260));
      await tester.pump();

      expect(gauntletOracle.value?.goalReached, isFalse);
      expect(gauntletOracle.value?.lastTapFraction, isNotNull);
    });
  });

  testWidgets('chart-read activates with Q3 as ground truth', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(const ChartReadScreen()));
    await tester.pump();
    expect(gauntletOracle.value?.scenarioId, 'vision/chart-read');
    expect(gauntletOracle.value?.expected['answer'], 'Q3');
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('ocr-price ground truth is not a semantic Text node', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(const OcrPriceScreen()));
    await tester.pump();
    expect(gauntletOracle.value?.expected['price'], r'$42.99');
    // The price is painted, so it must NOT be findable as a Text widget.
    expect(find.text(r'$42.99'), findsNothing);
  });

  testWidgets('count-spatial ground truth is 3', (WidgetTester tester) async {
    await tester.pumpWidget(_host(const CountSpatialScreen()));
    await tester.pump();
    expect(gauntletOracle.value?.expected['count'], 3);
  });

  testWidgets('semantics-lie: error tile reads "normal" in the tree', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(const SemanticsLieScreen()));
    await tester.pump();
    expect(gauntletOracle.value?.expected['error_tile'], 'Tile 3');
    // The lie: the red (error) tile's semantics still says "normal".
    expect(find.bySemanticsLabel('Tile 3, status normal'), findsOneWidget);
  });
}
