import 'dart:async';

import 'package:exploration_agent/exploration_agent.dart';

/// Test helper exposing a `Stream<TurnEvent>` plus `push`/`close` for
/// driving [ThinkingPanelController] without a real [ExplorationSession].
class TurnEventBus {
  final StreamController<TurnEvent> _c =
      StreamController<TurnEvent>.broadcast();

  Stream<TurnEvent> get stream => _c.stream;

  void push(TurnEvent e) => _c.add(e);

  Future<void> close() => _c.close();
}
