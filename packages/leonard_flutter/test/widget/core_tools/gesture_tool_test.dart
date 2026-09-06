import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:leonard_flutter/src/core_tools/dispatch.dart';

typedef _TimedPointerEvent = ({Duration elapsed, PointerEvent event});
typedef _GestureTarget = ({
  void Function() dispose,
  int id,
  LeonardTool gesture,
  SemanticsNode node,
});

class _PointerRecorder {
  _PointerRecorder() {
    _route = _record;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_route);
  }

  final Stopwatch _clock = Stopwatch()..start();
  final List<_TimedPointerEvent> _events = <_TimedPointerEvent>[];
  late final PointerRoute _route;

  void _record(PointerEvent event) {
    _events.add((elapsed: _clock.elapsed, event: event));
  }

  List<_TimedPointerEvent> take() {
    final List<_TimedPointerEvent> segment =
        List<_TimedPointerEvent>.unmodifiable(_events);
    _events.clear();
    return segment;
  }

  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_route);
    _clock.stop();
  }
}

void main() {
  test('schema_violation on unknown kind', () async {
    final SemanticsCapture cap = SemanticsCapture();
    final CoreExtension plugin = CoreExtension(semantics: cap);
    final LeonardTool g = plugin.tools.firstWhere(
      (LeonardTool t) => t.name == 'gesture',
    );
    final ToolResult r = await g.call(<String, Object?>{
      'node_id': 1,
      'kind': 'somersault',
    });
    expect(r.ok, isFalse);
    expect(r.error, contains('schema_violation'));
    cap.dispose();
  });

  test('schema_violation when distance_px out of range', () async {
    final SemanticsCapture cap = SemanticsCapture();
    final CoreExtension plugin = CoreExtension(semantics: cap);
    final LeonardTool g = plugin.tools.firstWhere(
      (LeonardTool t) => t.name == 'gesture',
    );
    final ToolResult r = await g.call(<String, Object?>{
      'node_id': 1,
      'kind': 'swipe',
      'direction': 'up',
      'distance_px': 5,
    });
    expect(r.ok, isFalse);
    expect(r.error, contains('schema_violation'));
    cap.dispose();
  });

  test('target_not_found before kind dispatch on unknown id', () async {
    final SemanticsCapture cap = SemanticsCapture();
    final CoreExtension plugin = CoreExtension(semantics: cap);
    final LeonardTool g = plugin.tools.firstWhere(
      (LeonardTool t) => t.name == 'gesture',
    );
    final ToolResult r = await g.call(<String, Object?>{
      'node_id': 9999,
      'kind': 'swipe',
      'direction': 'up',
      'distance_px': 50,
    });
    expect(r.ok, isFalse);
    expect(r.error, contains('target_not_found'));
    cap.dispose();
  });

  testWidgets('core.gesture swipe emits ordered linear positions and deltas', (
    WidgetTester tester,
  ) async {
    final _GestureTarget target = await _pumpGestureTarget(tester);
    final Rect rect = logicalRectOf(target.node);
    final Offset center = rect.center;
    final _PointerRecorder recorder = _PointerRecorder();
    addTearDown(recorder.dispose);

    final ToolResult result = (await tester.runAsync<ToolResult>(
      () => target.gesture.call(<String, Object?>{
        'node_id': target.id,
        'kind': 'swipe',
        'direction': 'up',
        'distance_px': 80,
      }),
    ))!;
    final List<_TimedPointerEvent> recorded = recorder.take();
    target.dispose();

    expect(result.ok, isTrue, reason: result.error);
    expect(
      recorded.map((_TimedPointerEvent e) => e.event.runtimeType),
      orderedEquals(<Type>[
        PointerDownEvent,
        PointerMoveEvent,
        PointerMoveEvent,
        PointerMoveEvent,
        PointerMoveEvent,
        PointerUpEvent,
      ]),
    );

    final int pointer = recorded.first.event.pointer;
    expect(
      recorded.map((_TimedPointerEvent e) => e.event.pointer),
      everyElement(pointer),
    );
    expect(recorded.first.event.position, center);

    final List<PointerMoveEvent> moves = recorded
        .sublist(1, 5)
        .map((_TimedPointerEvent e) => e.event as PointerMoveEvent)
        .toList(growable: false);
    for (int i = 0; i < moves.length; i++) {
      expect(moves[i].position, center.translate(0, -20.0 * (i + 1)));
      expect(moves[i].delta, const Offset(0, -20));
      if (i > 0) {
        expect(moves[i].position.dy, lessThan(moves[i - 1].position.dy));
      }
    }
    expect(recorded.last.event.position, center.translate(0, -80));
  });

  testWidgets('tap and long-press have distinct pointer timing and callbacks', (
    WidgetTester tester,
  ) async {
    int tapCount = 0;
    int longPressCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => tapCount++,
              onLongPress: () => longPressCount++,
              child: const SizedBox(width: 160, height: 160),
            ),
          ),
        ),
      ),
    );
    final Rect rect = tester.getRect(find.byType(GestureDetector));
    final _PointerRecorder recorder = _PointerRecorder();
    addTearDown(recorder.dispose);

    await tester.runAsync<void>(() => hitTestTap(rect));
    await tester.pump();
    final List<_TimedPointerEvent> tap = recorder.take();

    _expectPressStream(tap, rect.center);
    expect(
      tap.last.elapsed - tap.first.elapsed,
      lessThan(const Duration(milliseconds: 600)),
    );
    expect(tapCount, 1);
    expect(longPressCount, 0);

    await tester.runAsync<void>(() => hitTestLongPress(rect));
    await tester.pump();
    final List<_TimedPointerEvent> longPress = recorder.take();

    _expectPressStream(longPress, rect.center);
    expect(
      longPress.last.elapsed - longPress.first.elapsed,
      greaterThanOrEqualTo(const Duration(milliseconds: 600)),
    );
    expect(tapCount, 1);
    expect(longPressCount, 1);
  });

  group('core.gesture pinch stream', () {
    testWidgets('pinch_out reaches the requested span', (
      WidgetTester tester,
    ) async {
      await _expectPinchStream(tester, kind: 'pinch_out', scale: 2.0);
    });

    testWidgets('pinch_in reaches the requested span', (
      WidgetTester tester,
    ) async {
      await _expectPinchStream(tester, kind: 'pinch_in', scale: 0.5);
    });
  });

  testWidgets('hitTestDrag honors positive step pacing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.expand()));
    final _PointerRecorder recorder = _PointerRecorder();
    addTearDown(recorder.dispose);

    await tester.runAsync<void>(
      () => hitTestDrag(
        const Offset(10, 20),
        const Offset(30, 40),
        steps: 2,
        stepDuration: const Duration(milliseconds: 20),
      ),
    );
    final List<_TimedPointerEvent> recorded = recorder.take();

    expect(
      recorded.map((_TimedPointerEvent e) => e.event.runtimeType),
      orderedEquals(<Type>[
        PointerDownEvent,
        PointerMoveEvent,
        PointerMoveEvent,
        PointerUpEvent,
      ]),
    );
    expect(
      recorded.last.elapsed - recorded.first.elapsed,
      greaterThanOrEqualTo(const Duration(milliseconds: 40)),
    );
  });

  testWidgets('hitTestPinch honors positive step pacing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.expand()));
    final _PointerRecorder recorder = _PointerRecorder();
    addTearDown(recorder.dispose);

    await tester.runAsync<void>(
      () => hitTestPinch(
        const Offset(50, 50),
        startSpan: 20,
        endSpan: 40,
        steps: 2,
        stepDuration: const Duration(milliseconds: 20),
      ),
    );
    final List<_TimedPointerEvent> recorded = recorder.take();

    expect(
      recorded.map((_TimedPointerEvent e) => e.event.runtimeType),
      orderedEquals(<Type>[
        PointerDownEvent,
        PointerDownEvent,
        PointerMoveEvent,
        PointerMoveEvent,
        PointerMoveEvent,
        PointerMoveEvent,
        PointerUpEvent,
        PointerUpEvent,
      ]),
    );
    expect(
      recorded.last.elapsed - recorded.first.elapsed,
      greaterThanOrEqualTo(const Duration(milliseconds: 40)),
    );
  });

  test('requireField covers both integral-double guards', () {
    void expectCoerced(Object value) {
      final Map<String, Object?> args = <String, Object?>{'value': value};
      expect(requireField(args, 'value', int), isNull);
      expect(args['value'], allOf(isA<int>(), 3));
    }

    void expectSchemaViolation(Object value) {
      final Map<String, Object?> args = <String, Object?>{'value': value};
      final ToolResult? result = requireField(args, 'value', int);
      expect(result, isNotNull);
      expect(result!.ok, isFalse);
      expect(result.error, contains('schema_violation'));
    }

    expectCoerced(3.0);
    expectCoerced('3.0');
    expectSchemaViolation(3.5);
    expectSchemaViolation('3.5');
    expectSchemaViolation(double.infinity);
    expectSchemaViolation('Infinity');
    expectSchemaViolation(true);

    final Map<String, Object?> numArgs = <String, Object?>{'value': '3.5'};
    expect(requireField(numArgs, 'value', num), isNull);
    expect(numArgs['value'], allOf(isA<num>(), 3.5));

    final Map<String, Object?> doubleArgs = <String, Object?>{'value': '3.5'};
    expect(requireField(doubleArgs, 'value', double), isNull);
    expect(doubleArgs['value'], allOf(isA<double>(), 3.5));

    final Map<String, Object?> boolArgs = <String, Object?>{'value': true};
    expect(requireField(boolArgs, 'value', bool), isNull);
    expect(boolArgs['value'], isTrue);
  });
}

Future<_GestureTarget> _pumpGestureTarget(WidgetTester tester) async {
  final SemanticsHandle handle = tester.ensureSemantics();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: Semantics(
              container: true,
              label: 'pad',
              child: const ColoredBox(color: Color(0xFFEEEEEE)),
            ),
          ),
        ),
      ),
    ),
  );

  final SemanticsCapture capture = SemanticsCapture();
  final List<Map<String, Object>> records = await capture.captureAsync();
  final int id =
      records.firstWhere(
            (Map<String, Object> record) => record['label'] == 'pad',
          )['id']!
          as int;
  final CoreExtension plugin = CoreExtension(semantics: capture);
  final SemanticsNode? node = plugin.lookupNode(id);
  expect(node, isNotNull, reason: 'semantics target lookup failed');
  final LeonardTool gesture = plugin.tools.firstWhere(
    (LeonardTool tool) => tool.name == 'gesture',
  );
  return (
    dispose: () {
      capture.dispose();
      handle.dispose();
    },
    id: id,
    gesture: gesture,
    node: node!,
  );
}

void _expectPressStream(List<_TimedPointerEvent> recorded, Offset center) {
  expect(recorded, hasLength(2));
  expect(recorded.first.event, isA<PointerDownEvent>());
  expect(recorded.last.event, isA<PointerUpEvent>());
  expect(recorded.first.event.pointer, recorded.last.event.pointer);
  expect(recorded.first.event.position, center);
  expect(recorded.last.event.position, center);
}

Future<void> _expectPinchStream(
  WidgetTester tester, {
  required String kind,
  required double scale,
}) async {
  final _GestureTarget target = await _pumpGestureTarget(tester);
  final Rect rect = logicalRectOf(target.node);
  final Offset center = rect.center;
  final double startSpan = (rect.shortestSide / 4)
      .clamp(20.0, 200.0)
      .toDouble();
  final double endSpan = startSpan * scale;
  final double spanDelta = (endSpan - startSpan) / 8;
  final _PointerRecorder recorder = _PointerRecorder();
  addTearDown(recorder.dispose);

  final ToolResult result = (await tester.runAsync<ToolResult>(
    () => target.gesture.call(<String, Object?>{
      'node_id': target.id,
      'kind': kind,
      'scale': scale,
    }),
  ))!;
  final List<_TimedPointerEvent> recorded = recorder.take();
  target.dispose();

  expect(result.ok, isTrue, reason: result.error);
  expect(
    recorded.map((_TimedPointerEvent e) => e.event.runtimeType),
    orderedEquals(<Type>[
      PointerDownEvent,
      PointerDownEvent,
      ...List<Type>.filled(16, PointerMoveEvent),
      PointerUpEvent,
      PointerUpEvent,
    ]),
  );

  final int p0 = recorded[0].event.pointer;
  final int p1 = recorded[1].event.pointer;
  expect(p0, isNot(p1));
  expect(recorded[0].event.position, center.translate(-startSpan, 0));
  expect(recorded[1].event.position, center.translate(startSpan, 0));

  double previousSpan = startSpan;
  for (int i = 0; i < 8; i++) {
    final PointerMoveEvent move0 =
        recorded[2 + i * 2].event as PointerMoveEvent;
    final PointerMoveEvent move1 =
        recorded[3 + i * 2].event as PointerMoveEvent;
    final double expectedSpan = startSpan + spanDelta * (i + 1);

    expect(move0.pointer, p0);
    expect(move1.pointer, p1);
    expect(move0.position, center.translate(-expectedSpan, 0));
    expect(move1.position, center.translate(expectedSpan, 0));
    expect((move0.position.dx - center.dx).abs(), closeTo(expectedSpan, 1e-9));
    expect((move1.position.dx - center.dx).abs(), closeTo(expectedSpan, 1e-9));
    expect(move0.delta, Offset(-spanDelta, 0));
    expect(move1.delta, Offset(spanDelta, 0));
    expect(move0.delta, -move1.delta);
    expect(move0.delta.distance, closeTo(spanDelta.abs(), 1e-9));
    expect(move1.delta.distance, closeTo(spanDelta.abs(), 1e-9));
    expect(
      expectedSpan,
      endSpan > startSpan ? greaterThan(previousSpan) : lessThan(previousSpan),
    );
    previousSpan = expectedSpan;
  }

  expect(recorded[18].event.pointer, p0);
  expect(recorded[19].event.pointer, p1);
  expect(recorded[18].event.position, center.translate(-endSpan, 0));
  expect(recorded[19].event.position, center.translate(endSpan, 0));
}
