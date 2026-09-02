import 'package:dartantic_interface/dartantic_interface.dart';

/// How swift-infer should be told to pick a tool each turn.
enum SwiftInferToolChoice {
  /// `tool_choice: {type: any}` — force a tool call every turn (lenny default).
  any,

  /// `tool_choice: {type: auto}` — let the model decide.
  auto,
}

/// How much reasoning swift-infer's chat template budgets for a turn
/// (`reasoning_effort`). Non-Anthropic-standard.
///
/// The Qwen3.8 template runs `xhigh` when the field is absent, so lenny's
/// drivers set this explicitly on `qwen3.8` nodes.
enum SwiftInferReasoningEffort {
  /// Skip the reasoning phase.
  none,

  /// Minimal reasoning.
  low,

  /// lenny's driver default on `qwen3.8` nodes.
  medium,

  /// Extended reasoning.
  high,

  /// The Qwen3.8 template's own behaviour when `reasoning_effort` is absent.
  xhigh;

  /// The verbatim `reasoning_effort` wire value.
  String get wireValue => switch (this) {
    SwiftInferReasoningEffort.none => 'none',
    SwiftInferReasoningEffort.low => 'low',
    SwiftInferReasoningEffort.medium => 'medium',
    SwiftInferReasoningEffort.high => 'high',
    SwiftInferReasoningEffort.xhigh => 'xhigh',
  };

  /// Parses [wire] into an effort level, or `null` when it names no level.
  static SwiftInferReasoningEffort? tryParse(String wire) {
    for (final SwiftInferReasoningEffort e
        in SwiftInferReasoningEffort.values) {
      if (e.wireValue == wire) return e;
    }
    return null;
  }
}

/// Generation options for `SwiftInferChatModel`.
///
/// Carries the Qwen/MLX-tuned sampling knobs lenny can send to swift-infer's
/// Anthropic-compatible `/v1/messages` — including `presence_penalty`,
/// `repetition_penalty` and `reasoning_effort`, which are NOT expressible
/// through dartantic's `AnthropicChatOptions` (real Anthropic has no such
/// params). That gap is the reason swift-infer needs a custom `ChatModel`
/// rather than the stock `AnthropicChatModel` (ADR 0003 decision 4).
///
/// **Every sampling field defaults to `null`, and a `null` field is OMITTED
/// from the request body** so the swift-infer node's per-model-card defaults
/// apply. Set a field only to deliberately override the node.
/// [preserveThinking] is the one exception: it is a replay contract
/// (`lenny-eikx`), not a sampling knob, so it is always sent.
class SwiftInferChatOptions extends ChatModelOptions {
  /// Creates options; every unset sampling field is omitted from the body.
  const SwiftInferChatOptions({
    this.maxTokens,
    this.temperature,
    this.topP,
    this.topK,
    this.presencePenalty,
    this.repetitionPenalty,
    this.reasoningEffort,
    this.preserveThinking = true,
    this.stopSequences,
    this.toolChoice = SwiftInferToolChoice.any,
  });

  /// Maximum tokens in a single response (`max_tokens`); `null` omits it.
  final int? maxTokens;

  /// Sampling temperature (`temperature`); `null` omits it.
  final double? temperature;

  /// Nucleus-sampling top-p (`top_p`); `null` omits it.
  final double? topP;

  /// Top-k sampling cutoff (`top_k`); `null` omits it. Non-Anthropic-standard.
  final int? topK;

  /// Presence penalty (`presence_penalty`); `null` omits it.
  /// Non-Anthropic-standard.
  final double? presencePenalty;

  /// Repetition penalty (`repetition_penalty`); `null` omits it.
  /// Non-Anthropic-standard.
  final double? repetitionPenalty;

  /// Reasoning budget (`reasoning_effort`), sent as a TOP-LEVEL body field;
  /// `null` omits it. Non-Anthropic-standard.
  final SwiftInferReasoningEffort? reasoningEffort;

  /// Whether prior-turn reasoning is replayed to the gateway
  /// (`preserve_thinking`). When `true`, an assistant turn's [ThinkingPart]s
  /// are re-sent as a leading Anthropic `thinking` content block. Always
  /// written to the body — it is a replay contract, not a sampling knob.
  /// Non-Anthropic-standard.
  final bool preserveThinking;

  /// Optional stop sequences (`stop_sequences`).
  final List<String>? stopSequences;

  /// How `tool_choice` is set when tools are present.
  final SwiftInferToolChoice toolChoice;
}
