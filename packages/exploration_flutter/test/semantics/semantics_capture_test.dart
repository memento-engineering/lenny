import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('button captured; offscreen and excluded omitted',
      (WidgetTester tester) async {
    final SemanticsHandle h = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              Positioned(
                left: 10,
                top: 10,
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text('Submit'),
                ),
              ),
              const Positioned(
                left: -1000,
                top: -1000,
                child: Text('OffScreenLabel'),
              ),
              const ExcludeSemantics(child: Text('Hidden')),
            ],
          ),
        ),
      ),
    );
    final SemanticsCapture capture = SemanticsCapture();
    final List<Map<String, Object>> recs = capture.capture();
    final Iterable<Map<String, Object>> btns =
        recs.where((Map<String, Object> r) => r['role'] == 'button');
    expect(btns, hasLength(1));
    final Map<String, Object> btn = btns.first;
    expect(btn['label'], 'Submit');
    expect(btn['actions'], contains('tap'));
    expect(btn['rect'], isA<List<int>>());
    // Schema: only the documented keys are present on the button record.
    expect(
      btn.keys.toSet(),
      everyElement(isIn(<String>{
        'id',
        'role',
        'label',
        'state',
        'actions',
        'rect',
      })),
    );
    expect(btn.containsKey('id'), isTrue);
    expect(btn.containsKey('role'), isTrue);
    expect(btn.containsKey('rect'), isTrue);
    expect(
      recs.where((Map<String, Object> r) => r['label'] == 'OffScreenLabel'),
      isEmpty,
    );
    expect(
      recs.where((Map<String, Object> r) => r['label'] == 'Hidden'),
      isEmpty,
    );
    // Envelope shape returned by the VM extension wrapper.
    final Map<String, Object> env = <String, Object>{
      'semantics': recs,
      'count': recs.length,
    };
    expect(env['count'], recs.length);
    expect(env['semantics'], isA<List<Object?>>());
    capture.dispose();
    h.dispose();
  });

  testWidgets('stable ids across captures', (WidgetTester tester) async {
    final SemanticsHandle h = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            onPressed: () {},
            child: const Text('Go'),
          ),
        ),
      ),
    );
    final SemanticsCapture cap = SemanticsCapture();
    final Map<String, Object> a = cap
        .capture()
        .firstWhere((Map<String, Object> r) => r['label'] == 'Go');
    final Map<String, Object> b = cap
        .capture()
        .firstWhere((Map<String, Object> r) => r['label'] == 'Go');
    expect(b['id'], a['id']);
    cap.dispose();
    h.dispose();
  });

  testWidgets('lookup returns live SemanticsNode for emitted stable id',
      (WidgetTester tester) async {
    final SemanticsHandle h = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            onPressed: () {},
            child: const Text('Go'),
          ),
        ),
      ),
    );
    final SemanticsCapture cap = SemanticsCapture();
    final List<Map<String, Object>> recs = cap.capture();
    final Map<String, Object> btn =
        recs.firstWhere((Map<String, Object> r) => r['label'] == 'Go');
    final int stable = btn['id']! as int;
    final SemanticsNode? node = cap.lookup(stable);
    expect(node, isNotNull);
    expect(node!.getSemanticsData().label, 'Go');

    // Unknown stable id → null.
    expect(cap.lookup(999999), isNull);

    cap.dispose();
    h.dispose();
  });
}
