import 'dart:async';

import 'package:leonard_agent/leonard_agent.dart';

/// Test helper exposing a `Stream<TurnEvent>` plus `push`/`close` for
/// driving [ThinkingPanelController] without a real [LeonardSession].
class TurnEventBus {
  final StreamController<TurnEvent> _c =
      StreamController<TurnEvent>.broadcast();

  Stream<TurnEvent> get stream => _c.stream;

  void push(TurnEvent e) => _c.add(e);

  Future<void> close() => _c.close();
}
