import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('core.inspect_widget returns a depth-capped semantics subtree', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle h = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              ElevatedButton(onPressed: () {}, child: const Text('A')),
              ElevatedButton(onPressed: () {}, child: const Text('B')),
            ],
          ),
        ),
      ),
    );
    final SemanticsCapture cap = SemanticsCapture();
    final List<Map<String, Object>> recs = cap.capture();
    final int id =
        recs.firstWhere((Map<String, Object> r) => r['label'] == 'A')['id']!
            as int;
    final CoreExtension plugin = CoreExtension(semantics: cap);
    final LeonardTool t = plugin.tools.firstWhere(
      (LeonardTool x) => x.name == 'inspect_widget',
    );
    final ToolResult r = await t.call(<String, Object?>{
      'node_id': id,
      'depth': 3,
    });
    expect(r.ok, isTrue, reason: r.error);
    final Map<String, Object?> v = r.value! as Map<String, Object?>;
    expect(v.containsKey('tree'), isTrue);
    expect(v['truncated'], isFalse);
    final Map<String, Object?> tree = v['tree']! as Map<String, Object?>;
    expect(tree['role'], 'button');
    expect(tree['label'], 'A');
    cap.dispose();
    h.dispose();
  });

  test('schema_violation on bad depth', () async {
    final SemanticsCapture cap = SemanticsCapture();
    final CoreExtension plugin = CoreExtension(semantics: cap);
    final LeonardTool t = plugin.tools.firstWhere(
      (LeonardTool x) => x.name == 'inspect_widget',
    );
    final ToolResult r = await t.call(<String, Object?>{
      'node_id': 1,
      'depth': 20,
    });
    expect(r.ok, isFalse);
    expect(r.error, contains('schema_violation'));
    cap.dispose();
  });

  test('target_not_found on unknown id', () async {
    final SemanticsCapture cap = SemanticsCapture();
    final CoreExtension plugin = CoreExtension(semantics: cap);
    final LeonardTool t = plugin.tools.firstWhere(
      (LeonardTool x) => x.name == 'inspect_widget',
    );
    final ToolResult r = await t.call(<String, Object?>{'node_id': 9999});
    expect(r.ok, isFalse);
    expect(r.error, contains('target_not_found'));
    cap.dispose();
  });
}
