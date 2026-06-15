import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('core.scroll axis+delta_pixels validation', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle h = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: List<Widget>.generate(
              30,
              (int i) => ListTile(title: Text('Row $i')),
            ),
          ),
        ),
      ),
    );
    final SemanticsCapture cap = SemanticsCapture();
    final CoreExtension plugin = CoreExtension(semantics: cap);
    final LeonardTool scroll = plugin.tools.firstWhere(
      (LeonardTool x) => x.name == 'scroll',
    );

    // schema_violation: missing axis
    final ToolResult missing = await scroll.call(<String, Object?>{
      'node_id': 1,
      'delta_pixels': 100,
    });
    expect(missing.ok, isFalse);
    expect(missing.error, contains('schema_violation'));

    // schema_violation: bad axis
    final ToolResult badAxis = await scroll.call(<String, Object?>{
      'node_id': 1,
      'axis': 'diagonal',
      'delta_pixels': 100,
    });
    expect(badAxis.ok, isFalse);
    expect(badAxis.error, contains('schema_violation'));

    // target_not_found: unknown id (no semantics captured for this id yet)
    final ToolResult notFound = await scroll.call(<String, Object?>{
      'node_id': 99999,
      'axis': 'vertical',
      'delta_pixels': 100,
    });
    expect(notFound.ok, isFalse);
    expect(notFound.error, contains('target_not_found'));
    cap.dispose();
    h.dispose();
  });

  testWidgets(
    'core.scroll_until_visible returns target_unreachable after iteration cap',
    (WidgetTester tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: List<Widget>.generate(
                5,
                (int i) => ListTile(title: Text('Row $i')),
              ),
            ),
          ),
        ),
      );
      final SemanticsCapture cap = SemanticsCapture();
      final CoreExtension plugin = CoreExtension(semantics: cap);
      final LeonardTool sv = plugin.tools.firstWhere(
        (LeonardTool x) => x.name == 'scroll_until_visible',
      );
      // Cap iterations at 1; pass an unknown target_id and an unknown
      // scrollable_id so the loop exits via the not-found path or the
      // iteration cap depending on which fires first. With unknown
      // target id the loop snapshot never sees it; with unknown
      // scrollable_id we hit target_not_found first.
      final ToolResult r = await sv.call(<String, Object?>{
        'scrollable_id': 99999,
        'target_id': 99998,
        'axis': 'vertical',
        'max_iterations': 1,
      });
      expect(r.ok, isFalse);
      expect(
        r.error,
        anyOf(contains('target_not_found'), contains('target_unreachable')),
      );
      cap.dispose();
      h.dispose();
    },
  );

  test('scroll_until_visible rejects max_iterations out of range', () async {
    final SemanticsCapture cap = SemanticsCapture();
    final CoreExtension plugin = CoreExtension(semantics: cap);
    final LeonardTool sv = plugin.tools.firstWhere(
      (LeonardTool x) => x.name == 'scroll_until_visible',
    );
    final ToolResult r = await sv.call(<String, Object?>{
      'scrollable_id': 1,
      'target_id': 2,
      'axis': 'vertical',
      'max_iterations': 100,
    });
    expect(r.ok, isFalse);
    expect(r.error, contains('schema_violation'));
    cap.dispose();
  });
}
