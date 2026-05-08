/// OpenAI frontier model registry. Web-compatible.
///
/// Consumed by `OpenAiModelProvider`. Each entry advertises capabilities
/// per-model so the host can default behaviour (vision, context window).
library;

import '../types.dart';

/// One OpenAI model entry — id + capabilities.
class OpenAiModel {
  /// Build an [OpenAiModel] entry.
  const OpenAiModel({required this.id, required this.capabilities});

  /// Wire model id (e.g. `gpt-5`).
  final String id;

  /// Capabilities advertised to the host.
  final ModelCapabilities capabilities;
}

const ModelCapabilities _vision = ModelCapabilities(
  vision: true,
  preserveThinking: false,
  maxContext: 400000,
  supportsToolUse: true,
);

/// Known GPT-5-class models. Keyed by wire id.
const Map<String, OpenAiModel> openAiModels = <String, OpenAiModel>{
  'gpt-5': OpenAiModel(id: 'gpt-5', capabilities: _vision),
  'gpt-5-mini': OpenAiModel(id: 'gpt-5-mini', capabilities: _vision),
};
