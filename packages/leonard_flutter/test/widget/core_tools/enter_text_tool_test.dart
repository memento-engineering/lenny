import 'dart:async';

import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
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

      final CoreExtension plugin = CoreExtension(semantics: cap);
      final LeonardTool t = plugin.tools.firstWhere(
        (LeonardTool x) => x.name == 'enter_text',
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
    'core.enter_text coerces a string node_id ("5") to int — regression: '
    'qwen-mlx emits integer args as JSON strings',
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
      await tester.pump();

      final SemanticsCapture cap = SemanticsCapture();
      final List<Map<String, Object>> recs = cap.capture();
      final Map<String, Object> wrapper = recs.firstWhere(
        (Map<String, Object> r) =>
            r['role'] == 'textfield' && r['label'] == 'email',
      );
      final int id = wrapper['id']! as int;

      final CoreExtension plugin = CoreExtension(semantics: cap);
      final LeonardTool t = plugin.tools.firstWhere(
        (LeonardTool x) => x.name == 'enter_text',
      );
      // node_id passed as a STRING — the exact shape qwen-mlx emits.
      // Pre-fix, requireField rejected this as schema_violation.
      final ToolResult r = await t.call(<String, Object?>{
        'node_id': '$id',
        'text': 'coerced@test.com',
      });

      expect(r.ok, isTrue, reason: r.error);
      expect(ctrl.text, 'coerced@test.com');
      cap.dispose();
      h.dispose();
    },
  );

  testWidgets(
    'core.enter_text fires TextField.onChanged like real typing (regression: '
    'direct controller.value assignment left onChanged-driven state stale)',
    (WidgetTester tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      final TextEditingController ctrl = TextEditingController();
      addTearDown(ctrl.dispose);

      // App state updated only via onChanged — exactly the pattern from the
      // issue: a button gated on it. Pre-fix, enter_text assigned
      // controller.value directly, onChanged never fired, and the button
      // stayed disabled.
      String email = '';
      int submitted = 0;
      TextButton? nextButton;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, set) {
                nextButton = TextButton(
                  onPressed: email.contains('@') ? () {} : null,
                  child: const Text('Next'),
                );
                return Column(
                  children: [
                    Semantics(
                      label: 'email',
                      textField: true,
                      child: TextFormField(
                        controller: ctrl,
                        onChanged: (value) => set(() => email = value.trim()),
                        onFieldSubmitted: (_) => submitted++,
                      ),
                    ),
                    nextButton!,
                  ],
                );
              },
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

      final CoreExtension plugin = CoreExtension(semantics: cap);
      final LeonardTool t = plugin.tools.firstWhere(
        (LeonardTool x) => x.name == 'enter_text',
      );
      final ToolResult r = await t.call(<String, Object?>{
        'node_id': id,
        'text': 'user@example.com',
      });

      expect(r.ok, isTrue, reason: r.error);
      expect(ctrl.text, 'user@example.com');
      expect(
        email,
        'user@example.com',
        reason: 'onChanged must fire so app state updates',
      );
      // The onChanged-gated button is now enabled and tap-able.
      await tester.pump();
      expect(nextButton?.onPressed, isNotNull);
      // An edit is not a submit: onSubmitted/onFieldSubmitted fire from
      // _finalizeEditing via performAction, never from _formatAndSetValue.
      expect(
        submitted,
        0,
        reason: 'enter_text edits the field; it must not submit it',
      );
      cap.dispose();
      h.dispose();
    },
  );

  testWidgets('core.enter_text resolves the EditableText at devicePixelRatio>1 '
      '(regression: physical-px target rect vs logical-px render boxes)', (
    WidgetTester tester,
  ) async {
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

    final CoreExtension plugin = CoreExtension(semantics: cap);
    final LeonardTool t = plugin.tools.firstWhere(
      (LeonardTool x) => x.name == 'enter_text',
    );
    final ToolResult r = await t.call(<String, Object?>{
      'node_id': id,
      'text': 'dpr2@test.com',
    });

    expect(r.ok, isTrue, reason: r.error);
    expect(ctrl.text, 'dpr2@test.com');
    cap.dispose();
    h.dispose();
  });

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
      final CoreExtension plugin = CoreExtension(semantics: cap);
      final LeonardTool t = plugin.tools.firstWhere(
        (LeonardTool x) => x.name == 'enter_text',
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
    final CoreExtension plugin = CoreExtension(semantics: cap);
    final LeonardTool t = plugin.tools.firstWhere(
      (LeonardTool x) => x.name == 'enter_text',
    );
    final ToolResult r = await t.call(<String, Object?>{'node_id': 1});
    expect(r.ok, isFalse);
    expect(r.error, contains('schema_violation'));
    cap.dispose();
  });

  test('target_not_found on unknown id', () async {
    final SemanticsCapture cap = SemanticsCapture();
    final CoreExtension plugin = CoreExtension(semantics: cap);
    final LeonardTool t = plugin.tools.firstWhere(
      (LeonardTool x) => x.name == 'enter_text',
    );
    final ToolResult r = await t.call(<String, Object?>{
      'node_id': 9999,
      'text': 'x',
    });
    expect(r.ok, isFalse);
    expect(r.error, contains('target_not_found'));
    cap.dispose();
  });

  testWidgets(
    'core.enter_text skips an EditableText on a route that was never laid '
    'out (regression: a page stack built with the field route already '
    'covered threw "RenderBox was not laid out")',
    (WidgetTester tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      final TextEditingController hidden = TextEditingController();
      final TextEditingController visible = TextEditingController();
      addTearDown(hidden.dispose);
      addTearDown(visible.dispose);

      // Both pages are present from the first frame, so the Overlay never
      // lays out the covered one: its EditableText is attached but sizeless.
      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            pages: <Page<void>>[
              MaterialPage<void>(
                key: const ValueKey<String>('covered'),
                child: Scaffold(body: TextField(controller: hidden)),
              ),
              MaterialPage<void>(
                key: const ValueKey<String>('top'),
                child: Scaffold(
                  body: Semantics(
                    label: 'first name',
                    textField: true,
                    child: TextField(controller: visible),
                  ),
                ),
              ),
            ],
            onDidRemovePage: (Page<Object?> _) {},
          ),
        ),
      );
      await tester.pump();

      final SemanticsCapture cap = SemanticsCapture();
      final List<Map<String, Object>> recs = cap.capture();
      final Map<String, Object> wrapper = recs.firstWhere(
        (Map<String, Object> r) =>
            r['role'] == 'textfield' && r['label'] == 'first name',
      );
      final int id = wrapper['id']! as int;

      final CoreExtension plugin = CoreExtension(semantics: cap);
      final LeonardTool t = plugin.tools.firstWhere(
        (LeonardTool x) => x.name == 'enter_text',
      );
      final ToolResult r = await t.call(<String, Object?>{
        'node_id': id,
        'text': 'Lenny',
      });

      expect(r.ok, isTrue, reason: r.error);
      expect(visible.text, 'Lenny');
      expect(hidden.text, isEmpty);
      cap.dispose();
      h.dispose();
    },
  );

  // Enters [text] through core.enter_text on the textfield node labelled
  // [label].
  Future<ToolResult> enterTextAtLabel(String label, String text) async {
    final SemanticsCapture cap = SemanticsCapture();
    try {
      final Map<String, Object> wrapper = cap.capture().firstWhere(
        (Map<String, Object> r) =>
            r['role'] == 'textfield' && r['label'] == label,
      );
      final CoreExtension core = CoreExtension(semantics: cap);
      final LeonardTool t = core.tools.firstWhere(
        (LeonardTool x) => x.name == 'enter_text',
      );
      return await t.call(<String, Object?>{
        'node_id': wrapper['id']! as int,
        'text': text,
      });
    } finally {
      cap.dispose();
    }
  }

  // Area of the overlap between the EditableText driven by [field] and the
  // TextField driven by [target], whose rect is the target node's. Reads the
  // render boxes directly, so an off-stage field's stale geometry counts.
  double overlapArea(
    WidgetTester tester,
    TextEditingController field,
    TextEditingController target,
  ) {
    Rect rectOf(Finder f) {
      final RenderBox box = tester.renderObject<RenderBox>(f);
      return box.localToGlobal(Offset.zero) & box.size;
    }

    final Rect editable = rectOf(
      find.byWidgetPredicate(
        (Widget w) => w is EditableText && w.controller == field,
        skipOffstage: false,
      ),
    );
    final Rect targetRect = rectOf(
      find.byWidgetPredicate(
        (Widget w) => w is TextField && w.controller == target,
      ),
    );
    final Rect overlap = editable.intersect(targetRect);
    return overlap.isEmpty ? 0 : overlap.width * overlap.height;
  }

  // Pushes a field route over a laid-out field route at runtime, then enters
  // text through the node of the field on the pushed route. By default both
  // fields fill the same rect, so the geometric match ties; with
  // [hiddenOverlapsMore] the covered field overlaps the target more than the
  // visible one does, so only its being off stage rules it out. The semantics
  // handle is disposed in a finally: flutter_test checks for live handles
  // before addTearDown callbacks run.
  Future<void> enterTextOverLaidOutRoute(
    WidgetTester tester, {
    required bool opaque,
    bool hiddenOverlapsMore = false,
    required TextEditingController hidden,
    required TextEditingController visible,
  }) async {
    final SemanticsHandle h = tester.ensureSemantics();
    final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
    try {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: Scaffold(
            body: hiddenOverlapsMore
                ? TextField(controller: hidden, minLines: 2, maxLines: 2)
                : TextField(controller: hidden),
          ),
        ),
      );
      await tester.pump();

      final Widget top = Scaffold(
        body: Semantics(
          label: 'first name',
          textField: true,
          child: TextField(controller: visible),
        ),
      );
      unawaited(
        nav.currentState!.push(
          PageRouteBuilder<void>(opaque: opaque, pageBuilder: (_, _, _) => top),
        ),
      );
      await tester.pumpAndSettle();

      final double hiddenArea = overlapArea(tester, hidden, visible);
      final double visibleArea = overlapArea(tester, visible, visible);
      if (hiddenOverlapsMore) {
        expect(hiddenArea, greaterThan(visibleArea));
      } else {
        expect(hiddenArea, visibleArea);
      }

      final ToolResult r = await enterTextAtLabel('first name', 'Lenny');
      expect(r.ok, isTrue, reason: r.error);
      expect(visible.text, 'Lenny');
      expect(hidden.text, isEmpty);
    } finally {
      h.dispose();
    }
  }

  testWidgets(
    'core.enter_text skips an EditableText on a route covered after it was '
    'laid out (lenny-5bw3t: the covered field keeps its size and won the tie)',
    (WidgetTester tester) async {
      final TextEditingController hidden = TextEditingController();
      final TextEditingController visible = TextEditingController();
      addTearDown(hidden.dispose);
      addTearDown(visible.dispose);
      await enterTextOverLaidOutRoute(
        tester,
        opaque: true,
        hiddenOverlapsMore: true,
        hidden: hidden,
        visible: visible,
      );
    },
  );

  testWidgets(
    'core.enter_text prefers the topmost EditableText when a non-opaque '
    'route leaves the field beneath it on stage (lenny-5bw3t)',
    (WidgetTester tester) async {
      final TextEditingController hidden = TextEditingController();
      final TextEditingController visible = TextEditingController();
      addTearDown(hidden.dispose);
      addTearDown(visible.dispose);
      await enterTextOverLaidOutRoute(
        tester,
        opaque: false,
        hidden: hidden,
        visible: visible,
      );
    },
  );

  testWidgets(
    'core.enter_text skips an EditableText in an unselected IndexedStack '
    'child (lenny-5bw3t: a hidden tab is laid out at full geometry and, '
    'later in the tree, won the tie)',
    (WidgetTester tester) async {
      final TextEditingController hidden = TextEditingController();
      final TextEditingController visible = TextEditingController();
      addTearDown(hidden.dispose);
      addTearDown(visible.dispose);
      final SemanticsHandle h = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: IndexedStack(
                children: <Widget>[
                  Semantics(
                    label: 'search',
                    textField: true,
                    child: TextField(controller: visible),
                  ),
                  TextField(controller: hidden),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          overlapArea(tester, hidden, visible),
          overlapArea(tester, visible, visible),
        );

        final ToolResult r = await enterTextAtLabel('search', 'Lenny');
        expect(r.ok, isTrue, reason: r.error);
        expect(visible.text, 'Lenny');
        expect(hidden.text, isEmpty);
      } finally {
        h.dispose();
      }
    },
  );
}
