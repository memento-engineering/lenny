import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:leonard_flutter/src/core_tools/tools/tap_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('core.tap dispatches SemanticsAction.tap on a button', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle h = tester.ensureSemantics();
    int taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            onPressed: () => taps++,
            child: const Text('Submit'),
          ),
        ),
      ),
    );
    final SemanticsCapture cap = SemanticsCapture();
    final List<Map<String, Object>> recs = cap.capture();
    final int id =
        recs.firstWhere(
              (Map<String, Object> r) => r['label'] == 'Submit',
            )['id']!
            as int;

    final CoreExtension plugin = CoreExtension(semantics: cap);
    final LeonardTool tap = plugin.tools.firstWhere(
      (LeonardTool t) => t.name == 'tap',
    );
    final ToolResult r = await tap.call(<String, Object?>{'node_id': id});
    await tester.pump();
    expect(r.ok, isTrue, reason: r.error);
    expect(taps, 1);
    cap.dispose();
    h.dispose();
  });

  testWidgets('core.long_press dispatches SemanticsAction.longPress', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle h = tester.ensureSemantics();
    int longs = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GestureDetector(
            onLongPress: () => longs++,
            behavior: HitTestBehavior.opaque,
            child: Semantics(
              container: true,
              button: true,
              label: 'Hold',
              onLongPress: () => longs++,
              child: const SizedBox(width: 200, height: 60),
            ),
          ),
        ),
      ),
    );
    final SemanticsCapture cap = SemanticsCapture();
    final int id =
        cap.capture().firstWhere(
              (Map<String, Object> r) => r['label'] == 'Hold',
            )['id']!
            as int;
    final CoreExtension plugin = CoreExtension(semantics: cap);
    final LeonardTool lp = plugin.tools.firstWhere(
      (LeonardTool t) => t.name == 'long_press',
    );
    final ToolResult r = await lp.call(<String, Object?>{'node_id': id});
    await tester.pump();
    expect(r.ok, isTrue, reason: r.error);
    expect(longs, greaterThanOrEqualTo(1));
    cap.dispose();
    h.dispose();
  });

  test('schema_violation when node_id missing or wrong type', () async {
    final SemanticsCapture cap = SemanticsCapture();
    final CoreExtension plugin = CoreExtension(semantics: cap);
    final LeonardTool tap = plugin.tools.firstWhere(
      (LeonardTool t) => t.name == 'tap',
    );
    final ToolResult missing = await tap.call(const <String, Object?>{});
    expect(missing.ok, isFalse);
    expect(missing.error, contains('schema_violation'));
    final ToolResult wrong = await tap.call(<String, Object?>{
      'node_id': 'oops',
    });
    expect(wrong.ok, isFalse);
    expect(wrong.error, contains('schema_violation'));
    cap.dispose();
  });

  test('target_not_found on unknown id', () async {
    final SemanticsCapture cap = SemanticsCapture();
    final CoreExtension plugin = CoreExtension(semantics: cap);
    final LeonardTool tap = plugin.tools.firstWhere(
      (LeonardTool t) => t.name == 'tap',
    );
    final ToolResult r = await tap.call(<String, Object?>{'node_id': 9999});
    expect(r.ok, isFalse);
    expect(r.error, contains('target_not_found'));
    cap.dispose();
  });

  test('core.tap_at exposes the exact fractional coordinate schema', () {
    final SemanticsCapture cap = SemanticsCapture();
    final TapAtTool tapAt = TapAtTool(CoreExtension(semantics: cap));

    expect(
      tapAt.inputSchema.raw,
      equals(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'node_id': <String, Object?>{'type': 'integer', 'minimum': 1},
          'x': <String, Object?>{'type': 'number', 'minimum': 0, 'maximum': 1},
          'y': <String, Object?>{'type': 'number', 'minimum': 0, 'maximum': 1},
        },
        'required': <String>['node_id', 'x', 'y'],
        'additionalProperties': false,
      }),
    );
    cap.dispose();
  });

  testWidgets('core.tap_at dispatches at normalized node fractions', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle h = tester.ensureSemantics();
    Offset? received;
    const Key targetKey = ValueKey<String>('fractional-tap-target');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Semantics(
              container: true,
              label: 'Painted scene',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (TapDownDetails details) {
                  received = details.globalPosition;
                },
                child: const SizedBox(key: targetKey, width: 240, height: 120),
              ),
            ),
          ),
        ),
      ),
    );

    final SemanticsCapture cap = SemanticsCapture();
    final int id =
        cap.capture().firstWhere(
              (Map<String, Object> record) =>
                  record['label'] == 'Painted scene',
            )['id']!
            as int;
    final TapAtTool tapAt = TapAtTool(CoreExtension(semantics: cap));
    final ToolResult result = await tapAt.call(<String, Object?>{
      'node_id': id,
      'x': 0.8,
      'y': 0.25,
    });
    await tester.pump();

    final Rect targetRect = tester.getRect(find.byKey(targetKey));
    final Offset expected = Offset(
      targetRect.left + targetRect.width * 0.8,
      targetRect.top + targetRect.height * 0.25,
    );
    expect(result.ok, isTrue, reason: result.error);
    expect(received, isNotNull);
    expect(received!.dx, closeTo(expected.dx, 0.001));
    expect(received!.dy, closeTo(expected.dy, 0.001));
    expect(received, isNot(targetRect.center));
    cap.dispose();
    h.dispose();
  });

  test('core.tap_at rejects missing and wrong-typed fields', () async {
    final SemanticsCapture cap = SemanticsCapture();
    final TapAtTool tapAt = TapAtTool(CoreExtension(semantics: cap));
    final List<Map<String, Object?>> invalidArgs = <Map<String, Object?>>[
      <String, Object?>{'x': 0.5, 'y': 0.5},
      <String, Object?>{'node_id': 'one', 'x': 0.5, 'y': 0.5},
      <String, Object?>{'node_id': 1, 'y': 0.5},
      <String, Object?>{'node_id': 1, 'x': false, 'y': 0.5},
      <String, Object?>{'node_id': 1, 'x': 0.5},
      <String, Object?>{'node_id': 1, 'x': 0.5, 'y': false},
    ];

    for (final Map<String, Object?> args in invalidArgs) {
      final ToolResult result = await tapAt.call(args);
      expect(result.ok, isFalse, reason: '$args');
      expect(result.error, contains('schema_violation'), reason: '$args');
    }
    cap.dispose();
  });

  testWidgets('core.tap_at rejects invalid fractions without dispatching', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle h = tester.ensureSemantics();
    int taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Semantics(
          container: true,
          label: 'Guarded scene',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    final SemanticsCapture cap = SemanticsCapture();
    final int id =
        cap.capture().firstWhere(
              (Map<String, Object> record) =>
                  record['label'] == 'Guarded scene',
            )['id']!
            as int;
    final TapAtTool tapAt = TapAtTool(CoreExtension(semantics: cap));
    final List<Map<String, Object?>> invalidArgs = <Map<String, Object?>>[
      <String, Object?>{'node_id': id, 'x': -0.001, 'y': 0.5},
      <String, Object?>{'node_id': id, 'x': 1.001, 'y': 0.5},
      <String, Object?>{'node_id': id, 'x': 0.5, 'y': -0.001},
      <String, Object?>{'node_id': id, 'x': 0.5, 'y': 1.001},
      <String, Object?>{'node_id': id, 'x': double.nan, 'y': 0.5},
      <String, Object?>{'node_id': id, 'x': double.infinity, 'y': 0.5},
      <String, Object?>{'node_id': id, 'x': double.negativeInfinity, 'y': 0.5},
      <String, Object?>{'node_id': id, 'x': 0.5, 'y': double.nan},
      <String, Object?>{'node_id': id, 'x': 0.5, 'y': double.infinity},
      <String, Object?>{'node_id': id, 'x': 0.5, 'y': double.negativeInfinity},
    ];

    for (final Map<String, Object?> args in invalidArgs) {
      final ToolResult result = await tapAt.call(args);
      expect(result.ok, isFalse, reason: '$args');
      expect(result.error, contains('schema_violation'), reason: '$args');
    }
    await tester.pump();
    expect(taps, 0);
    cap.dispose();
    h.dispose();
  });

  test('core.tap_at returns target_not_found for an unknown id', () async {
    final SemanticsCapture cap = SemanticsCapture();
    final TapAtTool tapAt = TapAtTool(CoreExtension(semantics: cap));
    final ToolResult result = await tapAt.call(<String, Object?>{
      'node_id': 9999,
      'x': 0.5,
      'y': 0.5,
    });

    expect(result.ok, isFalse);
    expect(result.error, contains('target_not_found'));
    cap.dispose();
  });
}
