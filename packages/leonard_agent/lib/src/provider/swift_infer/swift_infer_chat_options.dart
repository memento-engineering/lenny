import 'package:dartantic_interface/dartantic_interface.dart';

/// How swift-infer should be told to pick a tool each turn.
enum SwiftInferToolChoice {
  /// `tool_choice: {type: any}` — force a tool call every turn (lenny default).
  any,

  /// `tool_choice: {type: auto}` — let the model decide.
  auto,
}

/// Generation options for [SwiftInferChatModel].
///
/// Carries the Qwen/MLX-tuned sampling knobs lenny sends to swift-infer's
/// Anthropic-compatible `/v1/messages` — including `presence_penalty` and
/// `repetition_penalty`, which are NOT expressible through dartantic's
/// `AnthropicChatOptions` (real Anthropic has no such params). That gap is the
/// reason swift-infer needs a custom `ChatModel` rather than the stock
/// `AnthropicChatModel` (ADR 0003).
///
/// Defaults mirror `SwiftInferConfig` (tuned for `qwen3.6-35b-a3b-8bit`
/// thinking mode, PRD §16.3).
class SwiftInferChatOptions extends ChatModelOptions {
  /// Creates options with lenny's swift-infer defaults.
  const SwiftInferChatOptions({
    this.maxTokens = 4096,
    this.temperature = 1.0,
    this.topP = 0.95,
    this.topK = 20,
    this.presencePenalty = 1.5,
    this.repetitionPenalty = 1.0,
    this.preserveThinking = true,
    this.stopSequences,
    this.toolChoice = SwiftInferToolChoice.any,
  });

  /// Maximum tokens in a single response (`max_tokens`).
  final int maxTokens;

  /// Sampling temperature (`temperature`).
  final double temperature;

  /// Nucleus-sampling top-p (`top_p`).
  final double topP;

  /// Top-k sampling cutoff (`top_k`). Non-Anthropic-standard.
  final int topK;

  /// Presence penalty (`presence_penalty`). Non-Anthropic-standard.
  final double presencePenalty;

  /// Repetition penalty (`repetition_penalty`). Non-Anthropic-standard.
  final double repetitionPenalty;

  /// Whether `<think>` reasoning is preserved across turns
  /// (`preserve_thinking`). Non-Anthropic-standard.
  final bool preserveThinking;

  /// Optional stop sequences (`stop_sequences`).
  final List<String>? stopSequences;

  /// How `tool_choice` is set when tools are present.
  final SwiftInferToolChoice toolChoice;
}
