/// Value types for the [ModelProvider] surface.
///
/// Web-compatible: pure Dart, no `dart:io`.
library;

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

/// Prompt payload handed to a [ModelProvider] for a single turn.
class PromptPayload {
  const PromptPayload({
    required this.systemMessage,
    required this.userMessages,
    required this.tools,
  });

  /// System-level instructions.
  final String systemMessage;

  /// User-role messages — each entry is a provider-agnostic content map
  /// (e.g. `{type: 'text', text: ...}`, `{type: 'image', ...}`).
  final List<Map<String, dynamic>> userMessages;

  /// Tools available on this turn — drives [ActionSchema] composition.
  final List<ToolDescriptor> tools;
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
    this.summaryUpdate,
    this.rationale,
    this.waitStrategy,
  });

  /// The action chosen this turn — `tool` is a tool name, `args` is the
  /// validated argument map for that tool.
  final ({String tool, Map<String, dynamic> args}) action;

  /// Optional update to the running run summary.
  final String? summaryUpdate;

  /// Optional rationale string (free-form; not used for control flow).
  final String? rationale;

  /// Optional wait strategy hint (e.g. `'frame'`, `'idle'`).
  final String? waitStrategy;
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
