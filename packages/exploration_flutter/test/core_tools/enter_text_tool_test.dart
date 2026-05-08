import 'package:exploration_flutter/contract.dart';
import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'core.enter_text dispatches setText via SemanticsAction.setText',
    (WidgetTester tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      String? received;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Semantics(
            container: true,
            textField: true,
            label: 'Name',
            onSetText: (String v) {
              received = v;
            },
            // Provide focus so the focus step is satisfied without the
            // hit-test fallback.
            onTap: () {},
            child: const SizedBox(width: 200, height: 40),
          ),
        ),
      ));
      final SemanticsCapture cap = SemanticsCapture();
      final List<Map<String, Object>> recs = cap.capture();
      final Map<String, Object> tf = recs.firstWhere(
        (Map<String, Object> r) => r['role'] == 'textfield',
      );
      final int id = tf['id']! as int;
      final CorePlugin plugin = CorePlugin(semantics: cap);
      final ExplorationTool t = plugin.tools
          .firstWhere((ExplorationTool x) => x.name == 'enter_text');
      final ToolResult r = await t.call(<String, Object?>{
        'node_id': id,
        'text': 'hello world',
      });
      await tester.pump();
      expect(r.ok, isTrue, reason: r.error);
      expect(received, 'hello world');
      cap.dispose();
      h.dispose();
    },
  );

  testWidgets(
    'core.enter_text returns target_unreachable when node has no setText',
    (WidgetTester tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            onPressed: () {},
            child: const Text('not a textfield'),
          ),
        ),
      ));
      final SemanticsCapture cap = SemanticsCapture();
      final int id = cap.capture().firstWhere(
              (Map<String, Object> r) => r['role'] == 'button')['id']!
          as int;
      final CorePlugin plugin = CorePlugin(semantics: cap);
      final ExplorationTool t = plugin.tools
          .firstWhere((ExplorationTool x) => x.name == 'enter_text');
      final ToolResult r = await t.call(<String, Object?>{
        'node_id': id,
        'text': 'x',
      });
      expect(r.ok, isFalse);
      expect(r.error, contains('target_unreachable'));
      cap.dispose();
      h.dispose();
    },
  );

  test('schema_violation when text missing', () async {
    final SemanticsCapture cap = SemanticsCapture();
    final CorePlugin plugin = CorePlugin(semantics: cap);
    final ExplorationTool t = plugin.tools
        .firstWhere((ExplorationTool x) => x.name == 'enter_text');
    final ToolResult r = await t.call(<String, Object?>{'node_id': 1});
    expect(r.ok, isFalse);
    expect(r.error, contains('schema_violation'));
    cap.dispose();
  });

  test('target_not_found on unknown id', () async {
    final SemanticsCapture cap = SemanticsCapture();
    final CorePlugin plugin = CorePlugin(semantics: cap);
    final ExplorationTool t = plugin.tools
        .firstWhere((ExplorationTool x) => x.name == 'enter_text');
    final ToolResult r = await t.call(<String, Object?>{
      'node_id': 9999,
      'text': 'x',
    });
    expect(r.ok, isFalse);
    expect(r.error, contains('target_not_found'));
    cap.dispose();
  });
}
