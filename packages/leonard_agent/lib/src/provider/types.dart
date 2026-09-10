/// Value types for the [ModelProvider] surface.
///
/// Web-compatible: pure Dart, no `dart:io`.
library;

import '../json_value.dart';
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

  /// Decodes a tool descriptor from its provider-wire representation.
  factory ToolDescriptor.fromJson(Map<String, dynamic> json) => ToolDescriptor(
    name: json['name'] as String,
    description: json['description'] as String,
    inputSchema: Map<String, dynamic>.from(
      json['input_schema'] as Map? ?? const <String, dynamic>{},
    ),
  );

  /// Pre-namespaced tool name, e.g. `core.tap`, `router.push`.
  final String name;

  /// Human-readable description surfaced to the model.
  final String description;

  /// JSON Schema (draft-07) fragment describing tool arguments.
  final Map<String, dynamic> inputSchema;

  /// Encodes this descriptor for transport across the provider boundary.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'description': description,
    'input_schema': inputSchema,
  };

  @override
  bool operator ==(Object other) =>
      other is ToolDescriptor &&
      name == other.name &&
      description == other.description &&
      jsonValuesEqual(inputSchema, other.inputSchema);

  @override
  int get hashCode =>
      Object.hash(name, description, jsonValueHash(inputSchema));
}

/// Sealed turn hierarchy for the append-only chat conversation
/// (chat-shape rebuild).
sealed class ConversationTurn {
  const ConversationTurn();

  /// Decodes a concrete turn using its explicit `type` discriminator.
  factory ConversationTurn.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      'user' => UserTurn.fromJson(json),
      'assistant' => AssistantTurn.fromJson(json),
      final Object? type => throw FormatException(
        'unknown conversation turn type: $type',
      ),
    };
  }

  /// Encodes this turn with a concrete `type` discriminator.
  Map<String, dynamic> toJson();
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

  /// Decodes a user-role conversation turn.
  factory UserTurn.fromJson(Map<String, dynamic> json) {
    final Object? rawToolResult = json['tool_result'];
    return UserTurn(
      observation: Observation.fromJson(
        Map<String, dynamic>.from(json['observation'] as Map),
      ),
      diff: ObservationDiff.fromJson(
        Map<String, dynamic>.from(json['diff'] as Map),
      ),
      toolResult: rawToolResult == null
          ? null
          : Map<String, dynamic>.from(rawToolResult as Map),
      trimmed: json['trimmed'] as bool? ?? false,
    );
  }

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

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': 'user',
    'observation': observation.toJson(),
    'diff': diff.toJson(),
    if (toolResult != null) 'tool_result': toolResult,
    'trimmed': trimmed,
  };

  @override
  bool operator ==(Object other) =>
      other is UserTurn &&
      observation == other.observation &&
      jsonValuesEqual(diff.toJson(), other.diff.toJson()) &&
      jsonValuesEqual(toolResult, other.toolResult) &&
      trimmed == other.trimmed;

  @override
  int get hashCode => Object.hash(
    observation,
    jsonValueHash(diff.toJson()),
    jsonValueHash(toolResult),
    trimmed,
  );
}

/// An assistant-role turn: the thinking trace (empty when absent) and
/// the tool call the model chose.
class AssistantTurn extends ConversationTurn {
  const AssistantTurn({required this.thinking, required this.action});

  /// Decodes an assistant-role conversation turn.
  factory AssistantTurn.fromJson(Map<String, dynamic> json) => AssistantTurn(
    thinking: json['thinking'] as String,
    action: _actionFromJson(json['action']),
  );

  final String thinking;
  final ({String tool, Map<String, dynamic> args}) action;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': 'assistant',
    'thinking': thinking,
    'action': _actionToJson(action),
  };

  @override
  bool operator ==(Object other) =>
      other is AssistantTurn &&
      thinking == other.thinking &&
      action.tool == other.action.tool &&
      jsonValuesEqual(action.args, other.action.args);

  @override
  int get hashCode =>
      Object.hash(thinking, action.tool, jsonValueHash(action.args));
}

/// Immutable snapshot of a chat-shape conversation at a point in time.
///
/// Replaces [PromptPayload] for providers built against the
/// chat-shape rebuild.
class ConversationSnapshot {
  const ConversationSnapshot({
    required this.systemMessage,
    required this.turns,
    required this.tools,
  });

  /// Decodes a conversation snapshot from the provider wire.
  factory ConversationSnapshot.fromJson(Map<String, dynamic> json) =>
      ConversationSnapshot(
        systemMessage: json['system_message'] as String,
        turns: <ConversationTurn>[
          for (final Object? value in json['turns'] as List? ?? const [])
            ConversationTurn.fromJson(Map<String, dynamic>.from(value as Map)),
        ],
        tools: <ToolDescriptor>[
          for (final Object? value in json['tools'] as List? ?? const [])
            ToolDescriptor.fromJson(Map<String, dynamic>.from(value as Map)),
        ],
      );

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

  /// Encodes this snapshot for transport across the provider boundary.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'system_message': systemMessage,
    'turns': turns.map((ConversationTurn turn) => turn.toJson()).toList(),
    'tools': tools.map((ToolDescriptor tool) => tool.toJson()).toList(),
  };

  @override
  bool operator ==(Object other) =>
      other is ConversationSnapshot &&
      systemMessage == other.systemMessage &&
      jsonValuesEqual(turns, other.turns) &&
      jsonValuesEqual(tools, other.tools);

  @override
  int get hashCode =>
      Object.hash(systemMessage, jsonValueHash(turns), jsonValueHash(tools));
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
    this.modelMetadata = const <String, dynamic>{},
  });

  /// Decodes a model decision from its provider-wire representation.
  factory ModelDecision.fromJson(Map<String, dynamic> json) => ModelDecision(
    action: _actionFromJson(json['action']),
    thinking: json['thinking'] as String?,
    rationale: json['rationale'] as String?,
    waitStrategy: json['wait_strategy'] as String?,
    providerRequestId: json['provider_request_id'] as String?,
    modelMetadata: Map<String, dynamic>.from(
      json['model_metadata'] as Map? ?? const <String, dynamic>{},
    ),
  );

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

  /// Provider response metadata persisted with the trajectory turn.
  /// Dartantic-backed providers include `served_model_id` and an explicit
  /// `provider_request_id` entry; custom providers may leave this empty.
  final Map<String, dynamic> modelMetadata;

  /// Encodes this decision for transport across the provider boundary.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'action': _actionToJson(action),
    if (thinking != null) 'thinking': thinking,
    if (rationale != null) 'rationale': rationale,
    if (waitStrategy != null) 'wait_strategy': waitStrategy,
    if (providerRequestId != null) 'provider_request_id': providerRequestId,
    'model_metadata': modelMetadata,
  };

  @override
  bool operator ==(Object other) =>
      other is ModelDecision &&
      action.tool == other.action.tool &&
      jsonValuesEqual(action.args, other.action.args) &&
      thinking == other.thinking &&
      rationale == other.rationale &&
      waitStrategy == other.waitStrategy &&
      providerRequestId == other.providerRequestId &&
      jsonValuesEqual(modelMetadata, other.modelMetadata);

  @override
  int get hashCode => Object.hash(
    action.tool,
    jsonValueHash(action.args),
    thinking,
    rationale,
    waitStrategy,
    providerRequestId,
    jsonValueHash(modelMetadata),
  );
}

/// One delta emitted on the [ModelProvider.thinking] stream.
class ThinkingDelta {
  const ThinkingDelta({required this.text, required this.isFinal});

  /// Decodes a thinking-stream delta from the provider wire.
  factory ThinkingDelta.fromJson(Map<String, dynamic> json) => ThinkingDelta(
    text: json['text'] as String,
    isFinal: json['is_final'] as bool,
  );

  /// Text fragment for the thinking panel.
  final String text;

  /// True when this delta is the last fragment of the current turn.
  final bool isFinal;

  /// Encodes this delta for transport across the provider boundary.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'text': text,
    'is_final': isFinal,
  };

  @override
  bool operator ==(Object other) =>
      other is ThinkingDelta && text == other.text && isFinal == other.isFinal;

  @override
  int get hashCode => Object.hash(text, isFinal);
}

/// Thrown when a model response fails JSON-Schema validation.
///
/// The loop driver catches this and retries the turn once with
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

({String tool, Map<String, dynamic> args}) _actionFromJson(Object? value) {
  final Map<String, dynamic> action = Map<String, dynamic>.from(value as Map);
  return (
    tool: action['tool'] as String,
    args: Map<String, dynamic>.from(
      action['args'] as Map? ?? const <String, dynamic>{},
    ),
  );
}

Map<String, dynamic> _actionToJson(
  ({String tool, Map<String, dynamic> args}) action,
) => <String, dynamic>{'tool': action.tool, 'args': action.args};
