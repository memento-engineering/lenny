import 'dart:async';

import 'package:exploration_agent/exploration_agent.dart';
import 'package:exploration_devtools/src/panels/prompt_panel_config.dart';
import 'package:exploration_devtools/src/panels/prompt_panel_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSession implements ExplorationSession {
  final StreamController<SessionProgressEvent> _ctrl =
      StreamController<SessionProgressEvent>.broadcast();
  bool started = false;
  bool ended = false;

  @override
  Stream<SessionProgressEvent> get progress => _ctrl.stream;

  @override
  Future<void> start(String goal, ExplorationConfig config) async {
    started = true;
    _ctrl.add(SessionStarted(goal));
  }

  @override
  Future<void> end() async {
    if (ended) return;
    ended = true;
    if (started) {
      _ctrl.add(const SessionEnded());
    }
    await _ctrl.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

const _cfg = PromptPanelConfig(
  goal: 'g',
  modelId: 'm',
  maxTurns: 1,
  wallClockBudget: Duration(minutes: 1),
  enabledPluginNamespaces: {},
);

void main() {
  test('start instantiates session and forwards events', () async {
    final fake = _FakeSession();
    final c = PromptPanelController(
      vmServiceUri: Uri.parse('ws://x'),
      factory: (_) async => fake,
    );
    final received = <SessionProgressEvent>[];
    c.events.listen(received.add);

    await c.start(_cfg);
    await Future<void>.delayed(Duration.zero);

    expect(fake.started, isTrue);
    expect(c.running, isTrue);
    expect(received, isNotEmpty);

    await c.dispose();
  });

  test('stop ends session and clears running flag', () async {
    final fake = _FakeSession();
    final c = PromptPanelController(
      vmServiceUri: Uri.parse('ws://x'),
      factory: (_) async => fake,
    );

    await c.start(_cfg);
    await c.stop();

    expect(fake.ended, isTrue);
    expect(c.running, isFalse);

    await c.dispose();
  });

  test('start while running throws', () async {
    final fake = _FakeSession();
    final c = PromptPanelController(
      vmServiceUri: Uri.parse('ws://x'),
      factory: (_) async => fake,
    );

    await c.start(_cfg);
    await expectLater(() => c.start(_cfg), throwsStateError);

    await c.dispose();
  });
}
