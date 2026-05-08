import 'package:exploration_flutter/contract.dart';
import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schema_violation on unknown kind', () async {
    final SemanticsCapture cap = SemanticsCapture();
    final CorePlugin plugin = CorePlugin(semantics: cap);
    final ExplorationTool g =
        plugin.tools.firstWhere((ExplorationTool t) => t.name == 'gesture');
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
    final CorePlugin plugin = CorePlugin(semantics: cap);
    final ExplorationTool g =
        plugin.tools.firstWhere((ExplorationTool t) => t.name == 'gesture');
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
    final CorePlugin plugin = CorePlugin(semantics: cap);
    final ExplorationTool g =
        plugin.tools.firstWhere((ExplorationTool t) => t.name == 'gesture');
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

  testWidgets('core.gesture pinch_out runs against a real node',
      (WidgetTester tester) async {
    final SemanticsHandle h = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
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
    ));
    final SemanticsCapture cap = SemanticsCapture();
    final List<Map<String, Object>> recs = cap.capture();
    final int id = recs
        .firstWhere((Map<String, Object> r) => r['label'] == 'pad')['id']! as int;
    final CorePlugin plugin = CorePlugin(semantics: cap);
    final ExplorationTool g =
        plugin.tools.firstWhere((ExplorationTool t) => t.name == 'gesture');
    final ToolResult r = await g.call(<String, Object?>{
      'node_id': id,
      'kind': 'pinch_out',
    });
    await tester.pump();
    expect(r.ok, isTrue, reason: r.error);
    cap.dispose();
    h.dispose();
  });
}
