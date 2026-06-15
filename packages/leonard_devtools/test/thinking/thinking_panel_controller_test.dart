import 'package:leonard_agent/leonard_agent.dart';
import 'package:leonard_devtools/src/thinking/thinking_panel_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_helpers/stub_turn_events.dart';

void main() {
  test('appends thinking deltas under same turn', () async {
    final bus = TurnEventBus();
    final c = ThinkingPanelController(bus.stream)..start();

    bus.push(
      const TurnThinking(1, ThinkingDelta(text: 'Hel', isFinal: false)),
    );
    bus.push(
      const TurnThinking(1, ThinkingDelta(text: 'lo', isFinal: false)),
    );
    await Future<void>.delayed(Duration.zero);

    expect(c.text.text, 'Hello');
    expect(c.currentTurn.value, 1);

    await c.dispose();
    await bus.close();
  });

  test('clears buffer on new turn', () async {
    final bus = TurnEventBus();
    final c = ThinkingPanelController(bus.stream)..start();

    bus.push(
      const TurnThinking(1, ThinkingDelta(text: 'first', isFinal: true)),
    );
    bus.push(
      const TurnThinking(2, ThinkingDelta(text: 'second', isFinal: false)),
    );
    await Future<void>.delayed(Duration.zero);

    expect(c.text.text, 'second');
    expect(c.currentTurn.value, 2);

    await c.dispose();
    await bus.close();
  });

  test('appends action and validation lines (ok)', () async {
    final bus = TurnEventBus();
    final c = ThinkingPanelController(bus.stream)..start();

    bus.push(
      const TurnThinking(1, ThinkingDelta(text: 'r', isFinal: true)),
    );
    bus.push(
      const TurnActionDecided(1, 'core.tap', <String, dynamic>{
        'node_id': 7,
      }),
    );
    bus.push(const TurnValidation(1, true, null));
    await Future<void>.delayed(Duration.zero);

    expect(c.text.text, contains('Action: core.tap(node_id: 7)'));
    expect(c.text.text, contains('Validation: ok'));

    await c.dispose();
    await bus.close();
  });

  test('appends validation reject reason', () async {
    final bus = TurnEventBus();
    final c = ThinkingPanelController(bus.stream)..start();

    bus.push(
      const TurnThinking(1, ThinkingDelta(text: 'r', isFinal: true)),
    );
    bus.push(
      const TurnActionDecided(1, 'core.tap', <String, dynamic>{
        'node_id': 9,
      }),
    );
    bus.push(const TurnValidation(1, false, 'unknown_node'));
    await Future<void>.delayed(Duration.zero);

    expect(c.text.text, contains('Validation: reject: unknown_node'));

    await c.dispose();
    await bus.close();
  });

  test('quotes string args in the action summary', () async {
    final bus = TurnEventBus();
    final c = ThinkingPanelController(bus.stream)..start();

    bus.push(
      const TurnActionDecided(0, 'router.go', <String, dynamic>{
        'route': '/home',
      }),
    );
    await Future<void>.delayed(Duration.zero);

    expect(c.text.text, contains('Action: router.go(route: "/home")'));

    await c.dispose();
    await bus.close();
  });

  test('cancels subscription on dispose', () async {
    final bus = TurnEventBus();
    final c = ThinkingPanelController(bus.stream)..start();
    await c.dispose();

    // Pushing after dispose must not throw, and the listener must not fire.
    bus.push(
      const TurnThinking(1, ThinkingDelta(text: 'late', isFinal: false)),
    );
    await Future<void>.delayed(Duration.zero);
    await bus.close();
  });

  test('start() twice throws', () async {
    final bus = TurnEventBus();
    final c = ThinkingPanelController(bus.stream)..start();
    expect(c.start, throwsStateError);
    await c.dispose();
    await bus.close();
  });
}
