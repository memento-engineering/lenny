import 'dart:async';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:flutter/foundation.dart';

import '../thinking/append_only_text_controller.dart';
import 'conversation_state.dart';

class ConversationViewModel extends ValueNotifier<ConversationState> {
  ConversationViewModel({
    required Stream<TurnEvent> turnEvents,
    required Stream<TrajectoryRecord> trajectory,
    int? maxTurns,
    DateTime? startedAt,
  }) : super(ConversationState(
          status: RunStatus.running,
          maxTurns: maxTurns,
          startedAt: startedAt ?? DateTime.now(),
        )) {
    _turnSub = turnEvents.listen(_onTurnEvent);
    _trajSub = trajectory.listen(_onTrajectoryRecord);
  }

  final Map<int, AppendOnlyTextController> _thinkingControllers = {};
  StreamSubscription<TurnEvent>? _turnSub;
  StreamSubscription<TrajectoryRecord>? _trajSub;
  bool _completed = false;

  // Exposed for TranscriptList/ConversationEntryView
  AppendOnlyTextController? thinkingControllerForTurn(int turn) =>
      _thinkingControllers[turn];

  // Called by ConversationScreen when the run ends (stop/done/error).
  void complete(RunStatus finalStatus) {
    if (_completed) return;
    _completed = true;
    value = value.copyWith(status: finalStatus);
  }

  void _onTurnEvent(TurnEvent e) {
    if (_completed) return;
    switch (e) {
      case TurnThinking(:final turn, :final delta):
        _thinkingControllers
            .putIfAbsent(turn, AppendOnlyTextController.new)
            .append(delta.text);
        // Add entry only if it doesn't already exist (trajectory may have
        // arrived before thinking events and already created the entry).
        final entryExists = value.entries.any((e) => e.turnIndex == turn);
        if (!entryExists) {
          value = value.copyWith(
            currentTurn: turn,
            entries: List.unmodifiable([
              ...value.entries,
              ConversationEntry(turnIndex: turn),
            ]),
          );
        } else if (turn > value.currentTurn) {
          value = value.copyWith(currentTurn: turn);
        }
        // Thinking text updates flow through AppendOnlyTextController
        // (not via value=); that way high-frequency token events do not
        // trigger a full ConversationState rebuild.
      case TurnActionDecided(:final turn, :final toolName, :final args):
        value = value.copyWith(
          entries: _updateEntry(
            turn,
            (e) => e.copyWith(toolName: toolName, toolArgs: args),
          ),
        );
      case TurnValidation(:final turn, :final ok):
        value = value.copyWith(
          entries: _updateEntry(turn, (e) => e.copyWith(validationOk: ok)),
        );
      case TurnUsage(:final estimatedTokens, :final trimBudget):
        value = value.copyWith(
          usage: UsageSnapshot(
            estimatedTokens: estimatedTokens,
            trimThreshold: trimBudget,
          ),
        );
      case TurnComplete():
        break; // lifecycle managed by complete() callback from screen
    }
  }

  void _onTrajectoryRecord(TrajectoryRecord r) {
    if (_completed || r is! TurnRecord) return;
    final result = _formatResult(r.executedAction);
    value = value.copyWith(
      entries: _updateEntry(
        r.index,
        (e) => e.copyWith(toolResult: result, complete: true),
        orElse: ConversationEntry(
          turnIndex: r.index,
          toolResult: result,
          complete: true,
        ),
      ),
    );
  }

  List<ConversationEntry> _updateEntry(
    int turnIndex,
    ConversationEntry Function(ConversationEntry) update, {
    ConversationEntry? orElse,
  }) {
    final idx = value.entries.indexWhere((e) => e.turnIndex == turnIndex);
    final updated = List<ConversationEntry>.of(value.entries);
    if (idx >= 0) {
      updated[idx] = update(updated[idx]);
    } else if (orElse != null) {
      updated.add(orElse);
    }
    return List.unmodifiable(updated);
  }

  static String _formatResult(Map<String, dynamic> exec) {
    final result = exec['result'];
    if (result == null) return '';
    if (result is Map) {
      if (result['ok'] == true) return '✓ ok';
      final err = result['error'];
      if (err != null) return '✗ ${err.toString()}';
    }
    return result.toString();
  }

  @override
  void dispose() {
    _turnSub?.cancel();
    _trajSub?.cancel();
    for (final ctl in _thinkingControllers.values) {
      ctl.dispose();
    }
    _thinkingControllers.clear();
    super.dispose();
  }
}
