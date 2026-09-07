import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:sample_app/gauntlet/scenario_oracle.dart';
import 'package:sample_app/gauntlet/scenarios/chart_read_screen.dart';
import 'package:sample_app/gauntlet/scenarios/count_spatial_screen.dart';
import 'package:sample_app/gauntlet/scenarios/object_id_screen.dart';
import 'package:sample_app/gauntlet/scenarios/ocr_price_screen.dart';
import 'package:sample_app/gauntlet/scenarios/semantics_lie_screen.dart';

Widget _host(Widget screen) => MaterialApp(home: screen);

Future<void> _tapSceneFraction(
  WidgetTester tester,
  Offset sceneFraction,
) async {
  final SemanticsCapture capture = SemanticsCapture();
  try {
    final Map<String, Object> root = (await capture.captureAsync()).first;
    final List<int> physicalRect = (root['rect']! as List).cast<int>();
    final double dpr = tester.view.devicePixelRatio;
    final Rect rootRect = Rect.fromLTRB(
      physicalRect[0] / dpr,
      physicalRect[1] / dpr,
      physicalRect[2] / dpr,
      physicalRect[3] / dpr,
    );
    final Rect sceneRect = tester.getRect(find.byKey(ObjectIdScreen.sceneKey));
    final Offset logicalPoint = Offset(
      sceneRect.left + sceneRect.width * sceneFraction.dx,
      sceneRect.top + sceneRect.height * sceneFraction.dy,
    );
    final double x = (logicalPoint.dx - rootRect.left) / rootRect.width;
    final double y = (logicalPoint.dy - rootRect.top) / rootRect.height;

    final CoreExtension core = CoreExtension(semantics: capture);
    final LeonardTool tap = core.tools.singleWhere(
      (LeonardTool tool) => tool.name == 'tap_at',
    );
    final ToolResult result = await tap.call(<String, Object?>{
      'node_id': root['id']! as int,
      'x': x,
      'y': y,
    });
    expect(result.ok, isTrue, reason: result.error);
  } finally {
    capture.dispose();
  }
}

void main() {
  tearDown(() => gauntletOracle.value = null);

  group('object-id (bbox tap oracle)', () {
    testWidgets('tap inside the red umbrella flips goal_reached', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(const ObjectIdScreen()));
      const Offset requested = Offset(0.78, 0.45);
      await _tapSceneFraction(tester, requested);
      await tester.pump();

      expect(gauntletOracle.value?.goalReached, isTrue);
      final Offset recorded = gauntletOracle.value!.lastTapFraction!;
      expect(recorded.dx, closeTo(requested.dx, 1e-9));
      expect(recorded.dy, closeTo(requested.dy, 1e-9));
    });

    testWidgets('tap on a different umbrella does NOT flip goal_reached', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(const ObjectIdScreen()));
      const Offset requested = Offset(0.24, 0.45);
      await _tapSceneFraction(tester, requested);
      await tester.pump();

      expect(gauntletOracle.value?.goalReached, isFalse);
      final Offset recorded = gauntletOracle.value!.lastTapFraction!;
      expect(recorded.dx, closeTo(requested.dx, 1e-9));
      expect(recorded.dy, closeTo(requested.dy, 1e-9));
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
