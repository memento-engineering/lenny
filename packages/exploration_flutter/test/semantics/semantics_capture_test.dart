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

  testWidgets(
    'nested rows get distinct device-space rects; stacked SwitchListTiles are '
    'captured as actionable switch nodes at DPR>1 (lenny-a3s)',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      final SemanticsHandle h = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('Settings')),
            body: ListView(
              children: <Widget>[
                SwitchListTile(
                  title: const Text('Dark Theme'),
                  value: false,
                  onChanged: (_) {},
                ),
                SwitchListTile(
                  title: const Text('Notifications'),
                  value: true,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final SemanticsCapture cap = SemanticsCapture();
      final List<Map<String, Object>> recs = cap.capture();

      Map<String, Object> sw(String label) => recs.firstWhere(
            (Map<String, Object> r) =>
                r['role'] == 'switch' && r['label'] == label,
          );
      final Map<String, Object> dark = sw('Dark Theme');
      final Map<String, Object> notif = sw('Notifications');

      // Both switches must be actionable, not dropped or demoted to text.
      expect(dark['actions'], contains('tap'));
      expect(notif['actions'], contains('tap'));

      // The defect (applying only the node's own transform) collapsed every
      // row to its parent-local origin, so both switches shared one rect and
      // _filterObscured dropped them. With ancestor transforms accumulated,
      // Notifications sits strictly below Dark Theme.
      final List<int> dr = (dark['rect']! as List).cast<int>();
      final List<int> nr = (notif['rect']! as List).cast<int>();
      expect(
        nr[1],
        greaterThan(dr[1]),
        reason: 'Notifications.top must be below Dark Theme.top; equal tops '
            'mean the rects collapsed (the bug). dark=$dr notif=$nr',
      );
      expect(dr, isNot(equals(nr)));

      cap.dispose();
      h.dispose();
    },
  );
}
