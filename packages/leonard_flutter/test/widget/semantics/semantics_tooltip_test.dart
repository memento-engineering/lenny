/// The tooltip-to-label promotion rule: Flutter puts an icon-only control's
/// hover text in `SemanticsData.tooltip`, so a driver that reads only `label`
/// sees an unlabeled button (the panel's Settings gear).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leonard_flutter/leonard_flutter.dart';

void main() {
  testWidgets('an icon-only button captures its tooltip as the label', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle h = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {},
          ),
        ),
      ),
    );
    final SemanticsCapture cap = SemanticsCapture();
    final List<Map<String, Object>> recs = await cap.captureAsync();
    final Iterable<Map<String, Object>> btns = recs.where(
      (Map<String, Object> r) => r['role'] == 'button',
    );
    expect(btns, hasLength(1));
    final Map<String, Object> btn = btns.first;
    expect(btn['label'], 'Settings');
    expect(btn['actions'], contains('tap'));
    // Promoted, not duplicated: the tooltip became the label, so no hint.
    expect(btn.containsKey('hint'), isFalse);
    cap.dispose();
    h.dispose();
  });

  testWidgets('a node with both a label and a tooltip keeps both, apart', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle h = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Semantics(
            label: 'Save',
            tooltip: 'Save the document',
            button: true,
            container: true,
            child: const SizedBox(width: 100, height: 40),
          ),
        ),
      ),
    );
    final SemanticsCapture cap = SemanticsCapture();
    final List<Map<String, Object>> recs = await cap.captureAsync();
    final Map<String, Object> node = recs.firstWhere(
      (Map<String, Object> r) => r['label'] == 'Save',
    );
    expect(node['hint'], 'Save the document');
    cap.dispose();
    h.dispose();
  });

  testWidgets('a node with neither a tooltip nor a label omits both keys', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle h = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Semantics(
            identifier: 'empty',
            container: true,
            child: const SizedBox(width: 100, height: 40),
          ),
        ),
      ),
    );
    final SemanticsCapture cap = SemanticsCapture();
    final List<Map<String, Object>> recs = await cap.captureAsync();
    final Map<String, Object> empty = recs.singleWhere(
      (Map<String, Object> r) => r['identifier'] == 'empty',
    );
    expect(empty.containsKey('label'), isFalse);
    expect(empty.containsKey('hint'), isFalse);
    cap.dispose();
    h.dispose();
  });
}
