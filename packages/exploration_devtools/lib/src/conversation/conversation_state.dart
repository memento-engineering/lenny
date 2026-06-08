import 'package:flutter/foundation.dart' show immutable;

enum RunStatus { idle, running, done, stopped, error }

@immutable
class UsageSnapshot {
  const UsageSnapshot({required this.estimatedTokens, this.trimThreshold});
  final int estimatedTokens;
  final int? trimThreshold;
  UsageSnapshot copyWith({int? estimatedTokens, int? trimThreshold}) =>
      UsageSnapshot(
        estimatedTokens: estimatedTokens ?? this.estimatedTokens,
        trimThreshold: trimThreshold ?? this.trimThreshold,
      );
}

@immutable
class ConversationEntry {
  const ConversationEntry({
    required this.turnIndex,
    this.toolName,
    this.toolArgs,
    this.validationOk,
    this.toolResult,
    this.complete = false,
  });
  final int turnIndex;
  final String? toolName;
  final Map<String, dynamic>? toolArgs;
  final bool? validationOk;
  final String? toolResult; // formatted summary; null until trajectory fills it
  final bool complete; // true once TurnRecord arrives for this turn

  ConversationEntry copyWith({
    String? toolName,
    Object? toolArgs = _sentinel,
    bool? validationOk,
    String? toolResult,
    bool? complete,
  }) =>
      ConversationEntry(
        turnIndex: turnIndex,
        toolName: toolName ?? this.toolName,
        toolArgs: toolArgs == _sentinel
            ? this.toolArgs
            : toolArgs as Map<String, dynamic>?,
        validationOk: validationOk ?? this.validationOk,
        toolResult: toolResult ?? this.toolResult,
        complete: complete ?? this.complete,
      );
}

// Sentinel for nullable copyWith; private to this file.
const Object _sentinel = Object();

@immutable
class ConversationState {
  const ConversationState({
    this.entries = const [],
    this.status = RunStatus.idle,
    this.usage,
    this.currentTurn = -1,
    this.maxTurns,
  });
  final List<ConversationEntry> entries; // unmodifiable; keyed by turnIndex
  final RunStatus status;
  final UsageSnapshot? usage;
  final int currentTurn; // -1 when idle
  final int? maxTurns; // from PromptPanelConfig.maxTurns

  ConversationState copyWith({
    List<ConversationEntry>? entries,
    RunStatus? status,
    UsageSnapshot? usage,
    int? currentTurn,
    int? maxTurns,
  }) =>
      ConversationState(
        entries: entries ?? this.entries,
        status: status ?? this.status,
        usage: usage ?? this.usage,
        currentTurn: currentTurn ?? this.currentTurn,
        maxTurns: maxTurns ?? this.maxTurns,
      );
}
