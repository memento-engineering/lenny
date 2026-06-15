import 'package:leonard_agent/leonard_agent.dart';
import 'package:leonard_devtools/src/thinking/thinking_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_helpers/stub_turn_events.dart';

void main() {
  testWidgets(
    'renders streaming text and does not show Jump-to-live by default',
    (t) async {
      final bus = TurnEventBus();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThinkingPanelFromStream(events: bus.stream),
          ),
        ),
      );

      for (int i = 0; i < 50; i++) {
        bus.push(
          TurnThinking(
            1,
            ThinkingDelta(text: 'token$i ', isFinal: false),
          ),
        );
      }
      await t.pumpAndSettle();

      expect(find.textContaining('token49'), findsOneWidget);
      expect(find.byKey(const Key('jump-to-live')), findsNothing);

      await bus.close();
    },
  );

  testWidgets(
    'manual scroll-up reveals Jump-to-live; tap resumes auto-scroll',
    (t) async {
      final bus = TurnEventBus();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              width: 400,
              child: ThinkingPanelFromStream(events: bus.stream),
            ),
          ),
        ),
      );

      // Push enough deltas to make the content scrollable. Each line ends
      // with `\n` so the content grows vertically.
      for (int i = 0; i < 400; i++) {
        bus.push(
          TurnThinking(
            1,
            ThinkingDelta(text: 'line$i\n', isFinal: false),
          ),
        );
      }
      await t.pumpAndSettle();

      // Initially auto-scrolled to the bottom; FAB hidden.
      expect(find.byKey(const Key('jump-to-live')), findsNothing);

      // Drag the scrollable content downwards by its top-center so the
      // scroll position decreases (i.e. user scrolls up). We use
      // `dragFrom` with an explicit point inside the panel's bounds to
      // avoid hit-test misses on the empty area below short text.
      final scrollable = find.byType(Scrollable).first;
      await t.drag(
        scrollable,
        const Offset(0, 800),
        warnIfMissed: false,
      );
      await t.pumpAndSettle();

      expect(find.byKey(const Key('jump-to-live')), findsOneWidget);

      await t.tap(find.byKey(const Key('jump-to-live')));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('jump-to-live')), findsNothing);

      await bus.close();
    },
  );

  testWidgets('renders Action and Validation lines after a turn',
      (t) async {
    final bus = TurnEventBus();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ThinkingPanelFromStream(events: bus.stream)),
      ),
    );

    bus.push(
      const TurnThinking(0, ThinkingDelta(text: 'reasoning', isFinal: true)),
    );
    bus.push(
      const TurnActionDecided(0, 'core.tap', <String, dynamic>{
        'node_id': 3,
      }),
    );
    bus.push(const TurnValidation(0, true, null));
    await t.pumpAndSettle();

    expect(
      find.textContaining('Action: core.tap(node_id: 3)'),
      findsOneWidget,
    );
    expect(find.textContaining('Validation: ok'), findsOneWidget);

    await bus.close();
  });
}
