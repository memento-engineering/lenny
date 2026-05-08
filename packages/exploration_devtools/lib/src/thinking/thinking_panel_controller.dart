/// Subscribes to a per-turn event stream and routes events into an
/// [AppendOnlyTextController] consumed by the Thinking panel widget.
///
/// Pure-Dart, web-compatible.
library;

import 'dart:async';

import 'package:exploration_agent/exploration_agent.dart';
import 'package:flutter/foundation.dart';

import 'append_only_text_controller.dart';

/// Routes [TurnEvent]s into:
///   * [text] — the rolling reasoning trace (cleared on each new turn).
///   * trailing `Action: ...` and `Validation: ...` lines after the
///     turn's action+validation events.
///
/// Owns its own subscription; call [dispose] to cancel.
class ThinkingPanelController {
  ThinkingPanelController(this._events);

  /// Constructor that subscribes to a session's [ExplorationSession.turnEvents].
  /// Equivalent to `ThinkingPanelController(session.turnEvents)`.
  factory ThinkingPanelController.forSession(ExplorationSession session) {
    return ThinkingPanelController(session.turnEvents);
  }

  final Stream<TurnEvent> _events;

  /// Append-only buffer driving the visible text.
  final AppendOnlyTextController text = AppendOnlyTextController();

  /// True when the panel auto-scrolls to the bottom on new tokens.
  /// Flipped to false on manual scroll-up; back to true via [resumeAutoScroll].
  final ValueNotifier<bool> autoScroll = ValueNotifier<bool>(true);

  /// Index of the turn currently streaming (initialised to -1 so the
  /// very first delta — typically turn 0 — triggers a buffer clear).
  final ValueNotifier<int> currentTurn = ValueNotifier<int>(-1);

  StreamSubscription<TurnEvent>? _sub;
  bool _disposed = false;

  /// Begin listening. Must be called exactly once.
  void start() {
    if (_sub != null) {
      throw StateError('ThinkingPanelController.start called twice');
    }
    _sub = _events.listen(_onEvent);
  }

  void _onEvent(TurnEvent e) {
    if (_disposed) return;
    if (e is TurnThinking) {
      if (e.turn != currentTurn.value) {
        text.clear();
        currentTurn.value = e.turn;
      }
      text.append(e.delta.text);
    } else if (e is TurnActionDecided) {
      text.append('\n\nAction: ${e.toolName}(${_argsSummary(e.args)})');
    } else if (e is TurnValidation) {
      final String body = e.ok
          ? 'ok'
          : 'reject: ${e.rejectReason ?? "(no reason)"}';
      text.append('\nValidation: $body\n');
    }
    // TurnComplete is intentionally not rendered — it's a control-flow
    // marker used by the timeline panel (.24).
  }

  /// Pause auto-scroll (called by the panel widget on a manual scroll-up).
  void pauseAutoScroll() => autoScroll.value = false;

  /// Resume auto-scroll (called by the panel widget when the user taps
  /// "Jump to live").
  void resumeAutoScroll() => autoScroll.value = true;

  /// Cancel the subscription and dispose owned listenables.
  Future<void> dispose() async {
    _disposed = true;
    await _sub?.cancel();
    _sub = null;
    text.dispose();
    autoScroll.dispose();
    currentTurn.dispose();
  }

  /// Renders an args map as `key: value, key: "string"` — strings are
  /// quoted, everything else uses `toString`.
  static String _argsSummary(Map<String, dynamic> a) => a.entries
      .map((kv) {
        final v = kv.value;
        return v is String ? '${kv.key}: "$v"' : '${kv.key}: $v';
      })
      .join(', ');
}
