/// The swift-infer sampling defaults lenny's drivers apply (the CLI factory
/// and the DevTools panel factory), kept in one place so the two consumers
/// cannot drift.
library;

import 'swift_infer_chat_options.dart';

/// Driver default for `max_tokens` on the swift-infer tier.
///
/// The previous 4096 capped thinking + answer together; a driver run has
/// already spent ~4.7k characters of thinking in a single turn.
const int kSwiftInferDriverMaxTokens = 16384;

/// Model-id prefix whose chat template runs `xhigh` when `reasoning_effort` is
/// absent. Mirrors the `startsWith('qwen3')` test in `capabilitiesFor`.
const String kQwen38IdPrefix = 'qwen3.8';

/// [SwiftInferReasoningEffort.medium] for a `qwen3.8` node, else `null` — an
/// unset effort is omitted from the body, leaving the node's card default.
SwiftInferReasoningEffort? defaultReasoningEffortFor(String modelId) =>
    modelId.startsWith(kQwen38IdPrefix)
    ? SwiftInferReasoningEffort.medium
    : null;

/// The options lenny's drivers send for [modelId]; each supplied override wins
/// over the default.
///
/// Only two fields are defaulted — [kSwiftInferDriverMaxTokens], and the
/// `qwen3.8` reasoning effort. Everything else is left unset so the node's
/// model-card defaults apply.
SwiftInferChatOptions defaultSwiftInferOptions(
  String modelId, {
  int? maxTokens,
  SwiftInferReasoningEffort? reasoningEffort,
  double? temperature,
  double? presencePenalty,
}) => SwiftInferChatOptions(
  maxTokens: maxTokens ?? kSwiftInferDriverMaxTokens,
  reasoningEffort: reasoningEffort ?? defaultReasoningEffortFor(modelId),
  temperature: temperature,
  presencePenalty: presencePenalty,
);
