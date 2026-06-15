/// Build a [ModelProvider] for a given [ModelTier] using PRD §16.4
/// per-tier defaults. The CLI is the only callsite — DevTools (.21)
/// builds providers via its own settings UI.
///
/// For the `qwen-mlx` tier, the factory mirrors `fs agent`'s wire
/// contract (`factoryskills/internal/agent/agent.go`):
///   * `SWIFT_INFER_AGENT_TOKEN` env var → `Authorization: Bearer …`.
///   * `SWIFT_INFER_ENDPOINT` env var → base URL (defaults to
///     `http://localhost:8080`).
///   * `conversationId` constructed as `exploration-<sessionId>-<unixMs>`
///     so every turn of one exploration run groups under one
///     conversation in the gateway dashboard.
///   * `captureBodies: true` so `GET /v1/conversations/<id>` returns the
///     captured request/response pairs.
library;

import 'dart:io' show Platform;

import 'package:leonard_agent/leonard_agent.dart';

import 'cli_args.dart';

/// Default swift-infer base URL for the local MLX gateway.
const String _kSwiftInferBaseUrl = 'http://localhost:8080';

/// Default MLX model id served by swift-infer (PRD §16.3 — qwen3.6
/// coder MoE, 8-bit quant). Must match an id the gateway advertises at
/// `GET /v1/models`; a stale id makes the gateway close the stream
/// mid-response.
const String _kSwiftInferModel = 'qwen3.6-35b-a3b-8bit';

/// Default Anthropic model id (Claude Sonnet 4.6).
const String _kAnthropicSonnet = 'claude-sonnet-4-6';

/// Default OpenAI model id (GPT-5).
const String _kOpenAiGpt5 = 'gpt-5';

/// Construct a [ModelProvider] for the chosen [tier] with PRD §16.4
/// defaults applied. Frontier tiers require an API key in the
/// environment; missing keys throw [StateError].
///
/// [sessionId] is required so the qwen-mlx tier can mint a stable
/// per-run `X-Conversation-Id` of the form `exploration-<sessionId>-<unixMs>`.
/// Pass [now] in tests to make the conversationId deterministic.
/// [onModelDiagnostics], when supplied, is forwarded to the Anthropic
/// provider's per-call diagnostics sink (latency, HTTP status,
/// stop_reason) so the CLI can surface API health on every model call.
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
    ModelTier.claude => AnthropicModelProvider(
        model: _kAnthropicSonnet,
        apiKey: _requireEnv('ANTHROPIC_API_KEY'),
        onCallDiagnostics: onModelDiagnostics,
      ),
    ModelTier.openai => OpenAiModelProvider(
        modelId: _kOpenAiGpt5,
        apiKey: _requireEnv('OPENAI_API_KEY'),
      ),
  };
}

/// Build the qwen-mlx provider with the fs-agent-symmetric env
/// contract. Extracted so the switch arm stays compact and the env
/// reads are easy to test.
SwiftInferModelProvider _buildSwiftInferProvider({
  required String sessionId,
  required DateTime Function() now,
}) {
  final String? envEndpoint = Platform.environment['SWIFT_INFER_ENDPOINT'];
  final String? envToken = Platform.environment['SWIFT_INFER_AGENT_TOKEN'];
  final Uri baseUrl = (envEndpoint != null && envEndpoint.isNotEmpty)
      ? Uri.parse(envEndpoint)
      : Uri.parse(_kSwiftInferBaseUrl);
  final int unixMs = now().millisecondsSinceEpoch;
  return SwiftInferModelProvider(
    config: SwiftInferConfig(
      baseUrl: baseUrl,
      model: _kSwiftInferModel,
      // PRD §16.3: Qwen3.6-35B-A3B is image-text-to-text and the CLI
      // defaults screenshots ON for the exploration agent. The
      // SwiftInferConfig default is `enableVision: false` (gated until
      // the gateway's VLM endpoint is verified), so the CLI overrides
      // it explicitly here.
      enableVision: true,
      bearerToken:
          (envToken != null && envToken.isNotEmpty) ? envToken : null,
      // captureBodies on by default for dev/PoC: gives us
      // `GET /v1/conversations/<id>` introspection for free.
      captureBodies: true,
      conversationId: 'exploration-$sessionId-$unixMs',
      sessionId: sessionId,
    ),
  );
}

String _requireEnv(String name) {
  final String? v = Platform.environment[name];
  if (v == null || v.isEmpty) {
    throw StateError('Missing required environment variable: $name');
  }
  return v;
}
