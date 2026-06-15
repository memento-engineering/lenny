/// Value types for the [ModelProvider] surface.
///
/// Web-compatible: pure Dart, no `dart:io`.
library;

import '../observation/diff_models.dart';
import '../observation/models.dart';

/// Description of a single tool available to the model on a given turn.
///
/// `inputSchema` is a JSON Schema (draft-07) fragment describing the
/// arguments accepted by the tool.
class ToolDescriptor {
  const ToolDescriptor({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  /// Pre-namespaced tool name, e.g. `core.tap`, `router.push`.
  final String name;

  /// Human-readable description surfaced to the model.
  final String description;

  /// JSON Schema (draft-07) fragment describing tool arguments.
  final Map<String, dynamic> inputSchema;
}

/// Sealed turn hierarchy for the append-only chat conversation
/// (lenny-wisp-cl4 chat-shape rebuild).
sealed class ConversationTurn {
  const ConversationTurn();
}

/// A user-role turn: one observation + diff from the loop driver, plus
/// an optional tool-result map for error feedback (schema/validation retry
/// or failed action). [trimmed] is set by
/// `ConversationBuilder.trimIfOverBudget`.
class UserTurn extends ConversationTurn {
  const UserTurn({
    required this.observation,
    required this.diff,
    this.toolResult,
    this.trimmed = false,
  });

  final Observation observation;
  final ObservationDiff diff;
  final Map<String, dynamic>? toolResult;
  final bool trimmed;

  UserTurn copyWith({Observation? observation, bool? trimmed}) => UserTurn(
    observation: observation ?? this.observation,
    diff: diff,
    toolResult: toolResult,
    trimmed: trimmed ?? this.trimmed,
  );
}

/// An assistant-role turn: the thinking trace (empty when absent) and
/// the tool call the model chose.
class AssistantTurn extends ConversationTurn {
  const AssistantTurn({required this.thinking, required this.action});

  final String thinking;
  final ({String tool, Map<String, dynamic> args}) action;
}

/// Immutable snapshot of a chat-shape conversation at a point in time.
///
/// Replaces [PromptPayload] for providers built against the
/// lenny-wisp-cl4 chat-shape rebuild.
class ConversationSnapshot {
  const ConversationSnapshot({
    required this.systemMessage,
    required this.turns,
    required this.tools,
  });

  final String systemMessage;
  final List<ConversationTurn> turns;
  final List<ToolDescriptor> tools;

  /// Returns a copy with [extraTurn] appended. The original is not mutated.
  /// Used by validation-retry to feed back schema/validation errors.
  ConversationSnapshot withAppended(ConversationTurn extraTurn) =>
      ConversationSnapshot(
        systemMessage: systemMessage,
        turns: List<ConversationTurn>.unmodifiable(<ConversationTurn>[
          ...turns,
          extraTurn,
        ]),
        tools: tools,
      );
}

/// Capabilities advertised by a [ModelProvider].
///
/// The host uses these to default behaviours — e.g. screenshot capture
/// is enabled when [vision] is true.
class ModelCapabilities {
  const ModelCapabilities({
    required this.vision,
    required this.preserveThinking,
    required this.maxContext,
    required this.supportsToolUse,
  });

  /// Whether the model accepts image inputs.
  final bool vision;

  /// Whether thinking/reasoning blocks must be preserved across turns.
  final bool preserveThinking;

  /// Maximum context window in tokens.
  final int maxContext;

  /// Whether the model exposes a structured tool-use API.
  final bool supportsToolUse;
}

/// One decision returned by [ModelProvider.decide].
class ModelDecision {
  const ModelDecision({
    required this.action,
    this.thinking,
    this.rationale,
    this.waitStrategy,
    this.providerRequestId,
  });

  /// The action chosen this turn — `tool` is a tool name, `args` is the
  /// validated argument map for that tool.
  final ({String tool, Map<String, dynamic> args}) action;

  /// Captured thinking/reasoning text for carry-forward to the next
  /// turn's [AssistantTurn]. Providers populate this from native
  /// thinking blocks (Anthropic), `<think>` tags (SwiftInfer), or
  /// leave it null (OpenAI).
  final String? thinking;

  /// Optional rationale string (free-form; not used for control flow).
  final String? rationale;

  /// Optional wait strategy hint (e.g. `'frame'`, `'idle'`).
  final String? waitStrategy;

  /// Provider-side request id (e.g. Anthropic/swift-infer `message.id`
  /// from the SSE `message_start` event). Null when the provider did
  /// not emit one, or when the decision was synthesized in tests.
  /// Surfaced into the dogfood trace as `decision.provider_request_id`
  /// so an operator can cross-reference swift-infer's
  /// `/v1/trace/:id` endpoint without manual time-correlation.
  final String? providerRequestId;
}

/// One delta emitted on the [ModelProvider.thinking] stream.
class ThinkingDelta {
  const ThinkingDelta({required this.text, required this.isFinal});

  /// Text fragment for the thinking panel.
  final String text;

  /// True when this delta is the last fragment of the current turn.
  final bool isFinal;
}

/// Thrown when a model response fails JSON-Schema validation.
///
/// The loop driver (.18) catches this and retries the turn once with
/// the [validationError] injected back into the prompt, per PRD §17.
class SchemaRejection implements Exception {
  const SchemaRejection({
    required this.validationError,
    required this.rawOutput,
  });

  /// Human-readable description of the validation failure.
  final String validationError;

  /// The raw model output that failed validation.
  final String rawOutput;

  @override
  String toString() => 'SchemaRejection: $validationError';
}
