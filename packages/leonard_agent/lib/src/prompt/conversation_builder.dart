/// Append-only chat-shape conversation manager (lenny-wisp-cl4).
///
/// Replaces the per-turn scratch-rebuild prompt assembler (PromptAssembler,
/// shipped by lenny-cx6.13) whose every-turn system-message mutation
/// invalidated the KV-cache prefix and dropped thinking traces between
/// turns. The system message is frozen at construction and never mutates;
/// each turn is appended via [appendUserTurn] / [appendAssistantTurn].
/// [trimIfOverBudget] drops observation content from the oldest non-trimmed
/// `UserTurn` to stay under a token estimate threshold.
library;

import '../observation/diff_models.dart';
import '../observation/models.dart';
import '../provider/types.dart';
import 'observation_renderer.dart';

class ConversationBuilder {
  ConversationBuilder({
    required String systemMessage,
    required List<ToolDescriptor> tools,
    ObservationRenderer? renderer,
  }) : _systemMessage = systemMessage,
       _tools = List<ToolDescriptor>.unmodifiable(tools),
       _renderer = renderer ?? const JsonObservationRenderer();

  final String _systemMessage;
  final List<ToolDescriptor> _tools;
  final ObservationRenderer _renderer;
  final List<ConversationTurn> _turns = <ConversationTurn>[];

  /// Append a user-role turn. [toolResult] carries a previous turn's
  /// failed-action error or a schema/validation-retry error map; null
  /// when this turn was a clean observation.
  void appendUserTurn(
    Observation obs,
    ObservationDiff diff, {
    Map<String, dynamic>? toolResult,
  }) {
    _turns.add(UserTurn(observation: obs, diff: diff, toolResult: toolResult));
  }

  /// Append an assistant-role turn — the thinking text (empty when the
  /// provider produced none) plus the validated tool call.
  void appendAssistantTurn(
    String thinking,
    ({String tool, Map<String, dynamic> args}) action,
  ) {
    _turns.add(AssistantTurn(thinking: thinking, action: action));
  }

  /// Immutable snapshot of the conversation state. The returned snapshot
  /// reuses the same system-message string instance across calls — Dart
  /// string canonicalisation makes the system prefix byte-identical for
  /// KV-cache friendliness.
  ConversationSnapshot snapshot() => ConversationSnapshot(
    systemMessage: _systemMessage,
    turns: List<ConversationTurn>.unmodifiable(_turns),
    tools: _tools,
  );

  /// Drop observation from the oldest non-trimmed [UserTurn] until
  /// [estimatedTokens] is `<= threshold` or no trimmable turns remain.
  /// Trimmed turns keep their [UserTurn.diff] intact so the model still
  /// sees the delta sequence; only the heavy observation body is
  /// replaced with [Observation.empty].
  void trimIfOverBudget(int threshold) {
    while (estimatedTokens() > threshold) {
      final int idx = _turns.indexWhere(
        (ConversationTurn t) => t is UserTurn && !t.trimmed,
      );
      if (idx < 0) break;
      _turns[idx] = (_turns[idx] as UserTurn).copyWith(
        observation: Observation.empty(),
        trimmed: true,
      );
    }
  }

  int estimatedTokens() {
    // Whitespace-split token estimate. Same logic as the deleted
    // WhitespaceTokenCounter.count() (cx6.13) — the counter abstraction
    // had exactly one consumer (PromptAssembler, also deleted), so
    // inlining here keeps the builder self-contained without reviving
    // a one-use type.
    int n = _systemMessage.split(RegExp(r'\s+')).length;
    for (final ConversationTurn t in _turns) {
      if (t is UserTurn) {
        n += t.trimmed
            ? 3
            : _renderer.render(t.observation).split(RegExp(r'\s+')).length;
        // Conservative flat-rate accounting for a screenshot content
        // block (cx6.7). Better to trim early than overflow.
        if (!t.trimmed && t.observation.screenshot != null) n += 1500;
      } else if (t is AssistantTurn) {
        n += t.thinking.split(RegExp(r'\s+')).length + 10;
      }
    }
    return n;
  }
}
