import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:exploration_flutter/src/core_tools/dispatch.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'hitTestTap synthesizes PointerDownEvent at logical center, not physical',
      (WidgetTester tester) async {
    // Set DPR to 2.0 so physical != logical coordinates.
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    // Pump a minimal widget so GestureBinding is wired up.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    // hitTestTap expects a logical-pixel rect. Construct one whose logical
    // center is (50, 60) — i.e. physical (100, 120) / DPR 2.0 = (50, 60).
    const Rect logicalRect = Rect.fromLTRB(0, 0, 100, 120);

    Offset? captured;
    void listener(PointerEvent event) {
      if (event is PointerDownEvent && captured == null) {
        captured = event.position;
      }
    }
    GestureBinding.instance.pointerRouter.addGlobalRoute(listener);
    addTearDown(
        () => GestureBinding.instance.pointerRouter.removeGlobalRoute(listener));

    await hitTestTap(logicalRect);
    await tester.pumpAndSettle();

    expect(captured, isNotNull, reason: 'no PointerDownEvent was synthesized');
    // logicalRect.center = (50, 60). That is what GestureBinding should receive.
    // Before the fix: callers passed globalRectOf (physical) directly, so
    // captured would be (100, 120) on DPR=2.
    expect(captured, equals(const Offset(50, 60)),
        reason: 'expected logical center (50,60); got $captured');
  });

  testWidgets(
      'logicalRectOf divides globalRectOf by devicePixelRatio',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Semantics(
        container: true,
        label: 'target',
        child: const SizedBox(width: 100, height: 100),
      ),
    ));

    // Retrieve the target node via SemanticsCapture.
    final SemanticsCapture cap = SemanticsCapture();
    final List<Map<String, Object>> recs = cap.capture();
    expect(recs, isNotEmpty, reason: 'no semantics nodes captured');

    final Map<String, Object> targetRec = recs.firstWhere(
        (Map<String, Object> r) => r['label'] == 'target');

    final int id = targetRec['id']! as int;
    final CorePlugin plugin = CorePlugin(semantics: cap);
    final SemanticsNode? node = plugin.lookupNode(id);
    expect(node, isNotNull, reason: 'node lookup failed');

    final Rect physical = globalRectOf(node!);
    final Rect logical = logicalRectOf(node);

    // Under DPR=2.0, logical dimensions should be half of physical.
    expect(logical.width, closeTo(physical.width / 2.0, 0.5));
    expect(logical.height, closeTo(physical.height / 2.0, 0.5));
    expect(logical.top, closeTo(physical.top / 2.0, 0.5));
    expect(logical.left, closeTo(physical.left / 2.0, 0.5));

    cap.dispose();
  });
}
