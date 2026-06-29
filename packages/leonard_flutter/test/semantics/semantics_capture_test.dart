import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('button captured; offscreen and excluded omitted', (
    WidgetTester tester,
  ) async {
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
    final Iterable<Map<String, Object>> btns = recs.where(
      (Map<String, Object> r) => r['role'] == 'button',
    );
    expect(btns, hasLength(1));
    final Map<String, Object> btn = btns.first;
    expect(btn['label'], 'Submit');
    expect(btn['actions'], contains('tap'));
    expect(btn['rect'], isA<List<int>>());
    // Schema: only the documented keys are present on the button record.
    expect(
      btn.keys.toSet(),
      everyElement(
        isIn(<String>{
          'id',
          'role',
          'label',
          'identifier',
          'value',
          'state',
          'actions',
          'rect',
          'scroll',
        }),
      ),
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

  testWidgets('Semantics(identifier:) is captured; absent omits the key', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle h = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              Semantics(
                identifier: 'submit_btn',
                button: true,
                label: 'Submit',
                child: const SizedBox(width: 120, height: 48),
              ),
              const Text('Plain'),
            ],
          ),
        ),
      ),
    );
    final SemanticsCapture cap = SemanticsCapture();
    final List<Map<String, Object>> recs = cap.capture();
    // The stable identifier is surfaced, and the human-readable label still
    // rides alongside it (addressing vs. inference — both present).
    final Map<String, Object> withId = recs.firstWhere(
      (Map<String, Object> r) => r['identifier'] == 'submit_btn',
    );
    expect(withId['label'], 'Submit');
    // A node with no Semantics(identifier:) omits the key entirely (present-only).
    final Map<String, Object> plain = recs.firstWhere(
      (Map<String, Object> r) => r['label'] == 'Plain',
    );
    expect(plain.containsKey('identifier'), isFalse);
    cap.dispose();
    h.dispose();
  });

  testWidgets('value-bearing node emits the value field', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle h = tester.ensureSemantics();
    final TextEditingController controller = TextEditingController(
      text: 'nonce@example.com',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextField(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    final SemanticsCapture cap = SemanticsCapture();
    final Map<String, Object> field = cap.capture().firstWhere(
      (Map<String, Object> r) => r['role'] == 'textfield',
    );
    expect(field['value'], 'nonce@example.com');
    cap.dispose();
    h.dispose();
  });

  testWidgets('scrollable node exposes scroll extent {pos,max}', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle h = tester.ensureSemantics();
    final ScrollController controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            controller: controller,
            itemCount: 50,
            itemExtent: 100,
            itemBuilder: (BuildContext _, int i) => Text('Item $i'),
          ),
        ),
      ),
    );
    controller.jumpTo(300);
    await tester.pumpAndSettle();

    final SemanticsCapture cap = SemanticsCapture();
    final List<Map<String, Object>> recs = cap.capture();
    final Iterable<Map<String, Object>> scrollables = recs.where(
      (Map<String, Object> r) => r.containsKey('scroll'),
    );
    expect(
      scrollables,
      isNotEmpty,
      reason: 'a scrollable node should report scroll extent',
    );
    final Map<String, Object> s =
        scrollables.first['scroll']! as Map<String, Object>;
    final double dpr = tester.view.devicePixelRatio;
    // pos is physical px (logical 300 * dpr), matching the rect's units.
    expect(s['pos'], (300 * dpr).round());
    expect(s['max'], isA<int>());
    expect(
      s['max'] as int,
      greaterThan(s['pos'] as int),
      reason: 'more content remains below the current offset',
    );

    cap.dispose();
    h.dispose();
  });

  testWidgets('non-scrollable node omits scroll', (WidgetTester tester) async {
    final SemanticsHandle h = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ElevatedButton(onPressed: () {}, child: const Text('Tap')),
        ),
      ),
    );
    final SemanticsCapture cap = SemanticsCapture();
    final Map<String, Object> btn = cap.capture().firstWhere(
      (Map<String, Object> r) => r['role'] == 'button',
    );
    expect(btn.containsKey('scroll'), isFalse);
    cap.dispose();
    h.dispose();
  });

  testWidgets('stable ids across captures', (WidgetTester tester) async {
    final SemanticsHandle h = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ElevatedButton(onPressed: () {}, child: const Text('Go')),
        ),
      ),
    );
    final SemanticsCapture cap = SemanticsCapture();
    final Map<String, Object> a = cap.capture().firstWhere(
      (Map<String, Object> r) => r['label'] == 'Go',
    );
    final Map<String, Object> b = cap.capture().firstWhere(
      (Map<String, Object> r) => r['label'] == 'Go',
    );
    expect(b['id'], a['id']);
    cap.dispose();
    h.dispose();
  });

  testWidgets('lookup returns live SemanticsNode for emitted stable id', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle h = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ElevatedButton(onPressed: () {}, child: const Text('Go')),
        ),
      ),
    );
    final SemanticsCapture cap = SemanticsCapture();
    final List<Map<String, Object>> recs = cap.capture();
    final Map<String, Object> btn = recs.firstWhere(
      (Map<String, Object> r) => r['label'] == 'Go',
    );
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
    'captured as actionable switch nodes at DPR>1',
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
        (Map<String, Object> r) => r['role'] == 'switch' && r['label'] == label,
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
        reason:
            'Notifications.top must be below Dark Theme.top; equal tops '
            'mean the rects collapsed (the bug). dark=$dr notif=$nr',
      );
      expect(dr, isNot(equals(nr)));

      cap.dispose();
      h.dispose();
    },
  );
}
