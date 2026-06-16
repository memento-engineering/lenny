/// Build a [ModelProvider] for a given [ModelTier] using PRD §16.4
/// per-tier defaults. The CLI is the only callsite — DevTools (.21)
/// builds providers via its own settings UI.
///
/// Post-dartantic-cutover (ADR 0003 / lenny-4dhv.4): every tier resolves to a
/// [DartanticModelProvider] over the corresponding [ModelBackendSpec].
///
/// For the `qwen-mlx` tier, the factory mirrors `fs agent`'s wire contract:
///   * `SWIFT_INFER_AGENT_TOKEN` env var → `Authorization: Bearer …`.
///   * `SWIFT_INFER_ENDPOINT` env var → base URL (defaults to
///     `http://localhost:8080`).
///   * `X-Conversation-Id` = `leonard-<sessionId>-<unixMs>` so every turn of
///     one run groups under one conversation in the gateway dashboard.
///   * `X-Swift-Infer-Capture-Bodies: true` for `GET /v1/conversations/<id>`.
library;

import 'dart:io' show Platform;

import 'package:leonard_agent/leonard_agent.dart';

import 'cli_args.dart';

/// Default swift-infer base URL for the local MLX gateway.
const String _kSwiftInferBaseUrl = 'http://localhost:8080';

/// Default MLX model id served by swift-infer (PRD §16.3 — qwen3.6
/// coder MoE, 8-bit quant).
const String _kSwiftInferModel = 'qwen3.6-35b-a3b-8bit';

/// Default Anthropic model id (Claude Sonnet 4.6).
const String _kAnthropicSonnet = 'claude-sonnet-4-6';

/// Default OpenAI model id (GPT-5).
const String _kOpenAiGpt5 = 'gpt-5';

/// Conservative capabilities when [capabilitiesFor] doesn't know the
/// (provider, model) pair — vision off, tool use on, generous context.
const ModelCapabilities _defaultCaps = ModelCapabilities(
  vision: false,
  preserveThinking: false,
  maxContext: 128000,
  supportsToolUse: true,
);

/// Construct a [ModelProvider] for the chosen [tier] with PRD §16.4
/// defaults applied. Frontier tiers require an API key in the
/// environment; missing keys throw [StateError].
///
/// [sessionId] is required so the qwen-mlx tier can mint a stable
/// per-run `X-Conversation-Id` of the form `leonard-<sessionId>-<unixMs>`.
/// Pass [now] in tests to make the conversationId deterministic.
///
/// [onModelDiagnostics] is retained for call-site compatibility but is a NO-OP
/// after the dartantic cutover — the seam has no per-call diagnostics sink.
/// Re-plumbing CLI API-health logging is a 4dhv follow-up.
ModelProvider buildProvider(
  ModelTier tier, {
  required String sessionId,
  DateTime Function()? now,
  void Function(Map<String, Object?> diagnostics)? onModelDiagnostics,
}) {
  return switch (tier) {
    ModelTier.qwenMlx => _buildSwiftInferProvider(
      sessionId: sessionId,
      now: now ?? DateTime.now,
    ),
    ModelTier.claude => DartanticModelProvider(
      backend: AnthropicBackend(apiKey: _requireEnv('ANTHROPIC_API_KEY')),
      model: _kAnthropicSonnet,
      capabilities:
          capabilitiesFor('anthropic', _kAnthropicSonnet) ?? _defaultCaps,
    ),
    ModelTier.openai => DartanticModelProvider(
      backend: OpenAIBackend(apiKey: _requireEnv('OPENAI_API_KEY')),
      model: _kOpenAiGpt5,
      capabilities: capabilitiesFor('openai', _kOpenAiGpt5) ?? _defaultCaps,
    ),
  };
}

/// Build the qwen-mlx provider with the fs-agent-symmetric env contract.
DartanticModelProvider _buildSwiftInferProvider({
  required String sessionId,
  required DateTime Function() now,
}) {
  final String? envEndpoint = Platform.environment['SWIFT_INFER_ENDPOINT'];
  final String? envToken = Platform.environment['SWIFT_INFER_AGENT_TOKEN'];
  final Uri baseUrl = (envEndpoint != null && envEndpoint.isNotEmpty)
      ? Uri.parse(envEndpoint)
      : Uri.parse(_kSwiftInferBaseUrl);
  final int unixMs = now().millisecondsSinceEpoch;
  return DartanticModelProvider(
    backend: SwiftInferBackend(
      baseUrl: baseUrl,
      bearerToken: (envToken != null && envToken.isNotEmpty) ? envToken : null,
      // PRD §16.3: Qwen3.6 is image-text-to-text and the CLI defaults
      // screenshots ON (vision comes from capabilitiesFor('swift-infer', …)).
      // captureBodies on by default for dev/PoC introspection.
      headers: <String, String>{
        'X-Conversation-Id': 'leonard-$sessionId-$unixMs',
        'X-Session-Id': sessionId,
        'X-Swift-Infer-Capture-Bodies': 'true',
      },
    ),
    model: _kSwiftInferModel,
    capabilities:
        capabilitiesFor('swift-infer', _kSwiftInferModel) ?? _defaultCaps,
  );
}

String _requireEnv(String name) {
  final String? v = Platform.environment[name];
  if (v == null || v.isEmpty) {
    throw StateError('Missing required environment variable: $name');
  }
  return v;
}
