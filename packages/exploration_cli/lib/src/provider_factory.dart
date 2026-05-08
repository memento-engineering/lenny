/// Build a [ModelProvider] for a given [ModelTier] using PRD §16.4
/// per-tier defaults. The CLI is the only callsite — DevTools (.21)
/// builds providers via its own settings UI.
library;

import 'dart:io' show Platform;

import 'package:exploration_agent/exploration_agent.dart';

import 'cli_args.dart';

/// Default swift-infer base URL for the local MLX gateway.
const String _kSwiftInferBaseUrl = 'http://localhost:8080';

/// Default MLX model id served by swift-infer (PRD §16.3 — qwen3.5
/// coder MoE, 8-bit quant).
const String _kSwiftInferModel = 'qwen3-35b-a3b';

/// Default Anthropic model id (Claude Sonnet 4.6).
const String _kAnthropicSonnet = 'claude-sonnet-4-6';

/// Default OpenAI model id (GPT-5).
const String _kOpenAiGpt5 = 'gpt-5';

/// Construct a [ModelProvider] for the chosen [tier] with PRD §16.4
/// defaults applied. Frontier tiers require an API key in the
/// environment; missing keys throw [StateError].
ModelProvider buildProvider(ModelTier tier) {
  return switch (tier) {
    ModelTier.qwenMlx => SwiftInferModelProvider(
        config: SwiftInferConfig(
          baseUrl: Uri.parse(_kSwiftInferBaseUrl),
          model: _kSwiftInferModel,
          // PRD §16.3: Qwen3.6-35B-A3B is image-text-to-text and the
          // CLI defaults screenshots ON for the exploration agent. The
          // SwiftInferConfig default is `enableVision: false` (gated
          // until the gateway's VLM endpoint is verified), so the CLI
          // overrides it explicitly here. Sampling/thinking defaults
          // (temp 1.0, top_p 0.95, top_k 20, presence 1.5, repetition
          // 1.0, preserve_thinking) are already the SwiftInferConfig
          // built-in defaults per PRD §16.3.
          enableVision: true,
        ),
      ),
    ModelTier.claude => AnthropicModelProvider(
        model: _kAnthropicSonnet,
        apiKey: _requireEnv('ANTHROPIC_API_KEY'),
      ),
    ModelTier.openai => OpenAiModelProvider(
        modelId: _kOpenAiGpt5,
        apiKey: _requireEnv('OPENAI_API_KEY'),
      ),
  };
}

String _requireEnv(String name) {
  final String? v = Platform.environment[name];
  if (v == null || v.isEmpty) {
    throw StateError('Missing required environment variable: $name');
  }
  return v;
}
