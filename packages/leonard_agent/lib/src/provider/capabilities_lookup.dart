/// Top-level [ModelCapabilities] lookup keyed by provider id + model id.
///
/// Lets a host (e.g. the DevTools prompt panel) advertise capability
/// hints (vision, thinking, max-context) for a model id without
/// instantiating a [ModelProvider]. Returns `null` for any unknown
/// (provider, model) pair so callers can render a "⚠ unknown
/// capabilities" badge and pick conservative defaults.
library;

import 'openai/openai_models.dart';
import 'types.dart';

/// Set of Claude model ids that accept image inputs (PRD §22). Public so a host
/// can advertise vision support without instantiating a provider. (Relocated
/// here from the deleted hand-rolled Anthropic provider — dartantic cutover,
/// ADR 0003 / lenny-4dhv.4.)
const kAnthropicVisionModels = <String>{'claude-sonnet-4-6', 'claude-opus-4-6'};

const ModelCapabilities _anthropicVisionCaps = ModelCapabilities(
  vision: true,
  preserveThinking: false,
  maxContext: 200000,
  supportsToolUse: true,
);

const ModelCapabilities _swiftInferQwenCaps = ModelCapabilities(
  vision: true,
  preserveThinking: true,
  // Matches the (now-deleted) hand-rolled SwiftInferModelProvider, which
  // advertised 128000; the seam reads capabilities from this lookup.
  maxContext: 128000,
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
