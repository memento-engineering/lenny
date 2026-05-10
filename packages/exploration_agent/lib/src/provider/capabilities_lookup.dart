/// Top-level [ModelCapabilities] lookup keyed by provider id + model id.
///
/// Lets a host (e.g. the DevTools prompt panel) advertise capability
/// hints (vision, thinking, max-context) for a model id without
/// instantiating a [ModelProvider]. Returns `null` for any unknown
/// (provider, model) pair so callers can render a "⚠ unknown
/// capabilities" badge and pick conservative defaults.
library;

import 'anthropic/anthropic_provider.dart';
import 'openai/openai_models.dart';
import 'types.dart';

const ModelCapabilities _anthropicVisionCaps = ModelCapabilities(
  vision: true,
  preserveThinking: false,
  maxContext: 200000,
  supportsToolUse: true,
);

const ModelCapabilities _swiftInferQwenCaps = ModelCapabilities(
  vision: true,
  preserveThinking: true,
  maxContext: 32768,
  supportsToolUse: true,
);

/// Resolve capabilities for the given (provider, model) pair.
///
/// Switches on [providerId]:
///   - `'anthropic'` — vision-tier caps iff [kAnthropicVisionModels]
///     contains [modelId]; otherwise `null` (unknown).
///   - `'openai'` — looks up [openAiModels]; returns the entry's
///     capabilities, or `null` if absent.
///   - `'swift-infer'` — qwen-tier caps iff [modelId] starts with
///     `'qwen3'`; otherwise `null`.
///   - anything else — `null`.
ModelCapabilities? capabilitiesFor(String providerId, String modelId) {
  switch (providerId) {
    case 'anthropic':
      return kAnthropicVisionModels.contains(modelId)
          ? _anthropicVisionCaps
          : null;
    case 'openai':
      return openAiModels[modelId]?.capabilities;
    case 'swift-infer':
      return modelId.startsWith('qwen3') ? _swiftInferQwenCaps : null;
    default:
      return null;
  }
}
