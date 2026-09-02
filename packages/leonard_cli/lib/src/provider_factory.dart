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
///   * `SWIFT_INFER_MODEL` env var → model id (defaults to
///     [_kSwiftInferModel]); the `modelId` argument (`--model-id`) outranks it.
///   * `SWIFT_INFER_REASONING_EFFORT` env var → `reasoning_effort`
///     (`none|low|medium|high|xhigh`); `--reasoning-effort` outranks it, and a
///     `qwen3.8` model id defaults to `medium`.
///   * `SWIFT_INFER_MAX_TOKENS` env var → `max_tokens`; `--max-tokens`
///     outranks it, and the driver default is 16384.
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
/// coder MoE, 8-bit quant). Overridden by `SWIFT_INFER_MODEL`, which is
/// itself overridden by `--model-id`.
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
/// [modelId] (the CLI's `--model-id`) pins the exact model id for the chosen
/// tier and outranks both `SWIFT_INFER_MODEL` and the per-tier constant; a
/// `null` or empty value leaves the tier default in force.
///
/// [environment] is the environment map every env read goes through; it
/// defaults to [Platform.environment] and is injected by tests (Fakes, not
/// mocks — a plain map IS the fake).
///
/// [onModelDiagnostics] is retained for call-site compatibility but is a NO-OP
/// after the dartantic cutover — the seam has no per-call diagnostics sink.
/// Re-plumbing CLI API-health logging is a 4dhv follow-up.
ModelProvider buildProvider(
  ModelTier tier, {
  required String sessionId,
  DateTime Function()? now,
  void Function(Map<String, Object?> diagnostics)? onModelDiagnostics,
  String? modelId,
  SwiftInferReasoningEffort? reasoningEffort,
  int? maxTokens,
  Map<String, String>? environment,
}) {
  final Map<String, String> env = environment ?? Platform.environment;
  final String anthropicModel = _resolveModelId(modelId, _kAnthropicSonnet);
  final String openAiModel = _resolveModelId(modelId, _kOpenAiGpt5);
  return switch (tier) {
    ModelTier.qwenMlx => _buildSwiftInferProvider(
      sessionId: sessionId,
      now: now ?? DateTime.now,
      environment: env,
      modelId: modelId,
      reasoningEffort: reasoningEffort,
      maxTokens: maxTokens,
    ),
    ModelTier.claude => DartanticModelProvider(
      backend: AnthropicBackend(apiKey: _requireEnv('ANTHROPIC_API_KEY', env)),
      model: anthropicModel,
      capabilities:
          capabilitiesFor('anthropic', anthropicModel) ?? _defaultCaps,
    ),
    ModelTier.openai => DartanticModelProvider(
      backend: OpenAIBackend(apiKey: _requireEnv('OPENAI_API_KEY', env)),
      model: openAiModel,
      capabilities: capabilitiesFor('openai', openAiModel) ?? _defaultCaps,
    ),
  };
}

/// The first non-empty of [override] then [fallback]. An empty string is
/// treated as "unset" so `SWIFT_INFER_MODEL=` behaves like an absent var,
/// matching the endpoint/token reads.
String _resolveModelId(String? override, String fallback) =>
    (override != null && override.isNotEmpty) ? override : fallback;

/// Build the qwen-mlx provider with the fs-agent-symmetric env contract.
///
/// Model-id precedence: [modelId] (`--model-id`) > `SWIFT_INFER_MODEL` >
/// [_kSwiftInferModel].
DartanticModelProvider _buildSwiftInferProvider({
  required String sessionId,
  required DateTime Function() now,
  required Map<String, String> environment,
  String? modelId,
  SwiftInferReasoningEffort? reasoningEffort,
  int? maxTokens,
}) {
  final String? envEndpoint = environment['SWIFT_INFER_ENDPOINT'];
  final String? envToken = environment['SWIFT_INFER_AGENT_TOKEN'];
  final String? envModel = environment['SWIFT_INFER_MODEL'];
  final Uri baseUrl = (envEndpoint != null && envEndpoint.isNotEmpty)
      ? Uri.parse(envEndpoint)
      : Uri.parse(_kSwiftInferBaseUrl);
  final String model = _resolveModelId(
    modelId,
    _resolveModelId(envModel, _kSwiftInferModel),
  );
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
      // Flag > env > per-model default; every other sampling field stays unset
      // so the node's model-card defaults apply.
      options: defaultSwiftInferOptions(
        model,
        maxTokens: maxTokens ?? _envMaxTokens(environment),
        reasoningEffort: reasoningEffort ?? _envReasoningEffort(environment),
      ),
    ),
    model: model,
    capabilities: capabilitiesFor('swift-infer', model) ?? _defaultCaps,
  );
}

/// `SWIFT_INFER_REASONING_EFFORT` → an effort level. An empty value is
/// "unset"; an unknown value is a LOUD [StateError], never a silent fallback.
SwiftInferReasoningEffort? _envReasoningEffort(
  Map<String, String> environment,
) {
  final String? raw = environment['SWIFT_INFER_REASONING_EFFORT'];
  if (raw == null || raw.trim().isEmpty) return null;
  final SwiftInferReasoningEffort? parsed = SwiftInferReasoningEffort.tryParse(
    raw.trim(),
  );
  if (parsed == null) {
    throw StateError(
      'Invalid SWIFT_INFER_REASONING_EFFORT: "$raw" '
      '(expected none, low, medium, high or xhigh)',
    );
  }
  return parsed;
}

/// `SWIFT_INFER_MAX_TOKENS` → a positive token budget. An empty value is
/// "unset"; a non-numeric or non-positive value is a LOUD [StateError].
int? _envMaxTokens(Map<String, String> environment) {
  final String? raw = environment['SWIFT_INFER_MAX_TOKENS'];
  if (raw == null || raw.trim().isEmpty) return null;
  final int? parsed = int.tryParse(raw.trim());
  if (parsed == null || parsed <= 0) {
    throw StateError(
      'Invalid SWIFT_INFER_MAX_TOKENS: "$raw" (expected a positive integer)',
    );
  }
  return parsed;
}

String _requireEnv(String name, Map<String, String> environment) {
  final String? v = environment[name];
  if (v == null || v.isEmpty) {
    throw StateError('Missing required environment variable: $name');
  }
  return v;
}
