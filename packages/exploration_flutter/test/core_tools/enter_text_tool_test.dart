import 'package:exploration_flutter/contract.dart';
import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'core.enter_text sets controller text via widget-tree path when called on wrapper node',
    (WidgetTester tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      final TextEditingController ctrl = TextEditingController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Semantics(
              label: 'email',
              textField: true,
              child: TextField(controller: ctrl),
            ),
          ),
        ),
      );
      // Force a frame so the element tree is fully built.
      await tester.pump();

      final SemanticsCapture cap = SemanticsCapture();
      final List<Map<String, Object>> recs = cap.capture();
      // Target the WRAPPER node (label == 'email', role == 'textfield',
      // which advertises NO actions — exactly the failure mode on device).
      final Map<String, Object> wrapper = recs.firstWhere(
        (Map<String, Object> r) =>
            r['role'] == 'textfield' && r['label'] == 'email',
      );
      final int id = wrapper['id']! as int;

      final CorePlugin plugin = CorePlugin(semantics: cap);
      final ExplorationTool t = plugin.tools.firstWhere(
        (ExplorationTool x) => x.name == 'enter_text',
      );
      final ToolResult r = await t.call(<String, Object?>{
        'node_id': id,
        'text': 'hello@test.com',
      });

      expect(r.ok, isTrue, reason: r.error);
      expect(ctrl.text, 'hello@test.com');
      expect(ctrl.selection, const TextSelection.collapsed(offset: 14));
      cap.dispose();
      h.dispose();
    },
  );

  testWidgets(
    'core.enter_text resolves the EditableText at devicePixelRatio>1 '
    '(regression: physical-px target rect vs logical-px render boxes, lenny-8k3)',
    (WidgetTester tester) async {
      // DPR>1 makes physical != logical. globalRectOf returns physical px while
      // resolveEditableText intersects against logical localToGlobal rects, so
      // the pre-fix code found no intersection and returned target_unreachable.
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetDevicePixelRatio);

      final SemanticsHandle h = tester.ensureSemantics();
      final TextEditingController ctrl = TextEditingController();
      addTearDown(ctrl.dispose);

      // Center the field so it is far from the origin: with DPR=2 the physical
      // rect (2x) and the logical render-box rect no longer overlap, which is
      // what makes the physical-vs-logical mismatch observable (a field at the
      // origin overlaps near y=0 regardless and would hide the bug).
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: Semantics(
                  label: 'email',
                  textField: true,
                  child: TextField(controller: ctrl),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final SemanticsCapture cap = SemanticsCapture();
      final Map<String, Object> wrapper = cap.capture().firstWhere(
        (Map<String, Object> r) =>
            r['role'] == 'textfield' && r['label'] == 'email',
      );
      final int id = wrapper['id']! as int;

      final CorePlugin plugin = CorePlugin(semantics: cap);
      final ExplorationTool t = plugin.tools.firstWhere(
        (ExplorationTool x) => x.name == 'enter_text',
      );
      final ToolResult r = await t.call(<String, Object?>{
        'node_id': id,
        'text': 'dpr2@test.com',
      });

      expect(r.ok, isTrue, reason: r.error);
      expect(ctrl.text, 'dpr2@test.com');
      cap.dispose();
      h.dispose();
    },
  );

  testWidgets(
    'core.enter_text returns target_unreachable when semantics node has no matching EditableText',
    (WidgetTester tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ElevatedButton(
              onPressed: () {},
              child: const Text('not a textfield'),
            ),
          ),
        ),
      );
      await tester.pump();
      final SemanticsCapture cap = SemanticsCapture();
      final int id =
          cap.capture().firstWhere(
                (Map<String, Object> r) => r['role'] == 'button',
              )['id']!
              as int;
      final CorePlugin plugin = CorePlugin(semantics: cap);
      final ExplorationTool t = plugin.tools.firstWhere(
        (ExplorationTool x) => x.name == 'enter_text',
      );
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
    final ExplorationTool t = plugin.tools.firstWhere(
      (ExplorationTool x) => x.name == 'enter_text',
    );
    final ToolResult r = await t.call(<String, Object?>{'node_id': 1});
    expect(r.ok, isFalse);
    expect(r.error, contains('schema_violation'));
    cap.dispose();
  });

  test('target_not_found on unknown id', () async {
    final SemanticsCapture cap = SemanticsCapture();
    final CorePlugin plugin = CorePlugin(semantics: cap);
    final ExplorationTool t = plugin.tools.firstWhere(
      (ExplorationTool x) => x.name == 'enter_text',
    );
    final ToolResult r = await t.call(<String, Object?>{
      'node_id': 9999,
      'text': 'x',
    });
    expect(r.ok, isFalse);
    expect(r.error, contains('target_not_found'));
    cap.dispose();
  });
}
