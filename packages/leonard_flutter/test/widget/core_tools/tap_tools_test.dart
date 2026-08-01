import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
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
}
