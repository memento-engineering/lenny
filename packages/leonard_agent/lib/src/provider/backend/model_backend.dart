import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:http/http.dart' as http;

import '../swift_infer/swift_infer_chat_model.dart';
import '../swift_infer/swift_infer_chat_options.dart';

/// Declarative description of a model backend the agent can drive, independent
/// of how it is wired (ADR 0003, lenny-4dhv.2).
///
/// Every backend resolves to a dartantic [ChatModel] via [buildBackendChatModel]
/// so the `ModelProvider` seam (lenny-4dhv.3) stays backend-agnostic. swift-infer
/// uses lenny's custom [SwiftInferChatModel]; the frontier backends use stock
/// dartantic models.
sealed class ModelBackendSpec {
  const ModelBackendSpec();
}

/// swift-infer (local MLX, Anthropic-compatible wire) via the custom
/// [SwiftInferChatModel] — the backend that needed lenient SSE parsing and the
/// Qwen sampling knobs (lenny-4dhv.1).
class SwiftInferBackend extends ModelBackendSpec {
  /// Creates a swift-infer backend spec.
  const SwiftInferBackend({
    required this.baseUrl,
    this.bearerToken,
    this.headers = const {},
    this.options,
  });

  /// Bare origin of the swift-infer gateway (e.g. `http://localhost:8080`).
  final Uri baseUrl;

  /// Bearer token sent as `Authorization: Bearer <token>` when non-empty.
  final String? bearerToken;

  /// Per-session swift-infer headers (X-Conversation-Id / X-Session-Id / ...).
  final Map<String, String> headers;

  /// Qwen-tuned sampling defaults; `null` uses [SwiftInferChatOptions] defaults.
  final SwiftInferChatOptions? options;
}

/// Anthropic (Claude) via stock dartantic [AnthropicChatModel].
///
/// The Anthropic chat model uses the supplied/native HTTP client directly (it
/// does NOT wrap it in dartantic's `RetryHttpClient`), so the loop driver keeps
/// full retry ownership — lenny's `SchemaRejection` contract is preserved.
class AnthropicBackend extends ModelBackendSpec {
  /// Creates an Anthropic backend spec.
  const AnthropicBackend({
    required this.apiKey,
    this.baseUrl,
    this.headers,
    this.enableThinking = true,
    this.options,
  });

  /// Anthropic API key (sent as `x-api-key`). For an Anthropic-compatible
  /// gateway needing `Authorization: Bearer`, set it via [headers] instead.
  final String apiKey;

  /// Override endpoint (bare origin); defaults to api.anthropic.com.
  final Uri? baseUrl;

  /// Extra headers (override internal headers on conflict).
  final Map<String, String>? headers;

  /// Whether extended thinking is enabled.
  final bool enableThinking;

  /// Anthropic sampling options.
  final AnthropicChatOptions? options;
}

/// OpenAI (or any OpenAI-compatible endpoint) via stock dartantic
/// [OpenAIProvider] / [OpenAIChatModel].
///
/// Note: the OpenAI path force-wraps a transport-only `RetryHttpClient`
/// (429 / 5xx / IO). That retry does NOT re-sample on a schema rejection (a 200
/// with bad content), so the decision-retry contract is intact; it only removes
/// driver control over *transport* retries on this backend.
class OpenAIBackend extends ModelBackendSpec {
  /// Creates an OpenAI backend spec.
  const OpenAIBackend({
    required this.apiKey,
    this.baseUrl,
    this.headers,
    this.enableThinking = false,
    this.temperature,
    this.options,
  });

  /// OpenAI API key.
  final String apiKey;

  /// Override endpoint (e.g. an OpenAI-compatible gateway `/v1`).
  final Uri? baseUrl;

  /// Extra headers.
  final Map<String, String>? headers;

  /// Whether reasoning is requested (only honoured by reasoning-capable models;
  /// the OpenAI Chat Completions path does not surface thinking).
  final bool enableThinking;

  /// Sampling temperature.
  final double? temperature;

  /// OpenAI sampling options.
  final OpenAIChatOptions? options;
}

/// Builds a configured dartantic [ChatModel] for [spec].
///
/// [model] is the model id; [tools] are the tools to offer (names must already
/// be Anthropic-legal — the seam owns lenny's dotted-name encoding). A supplied
/// [client] is used directly on the swift-infer and Anthropic paths (so the
/// driver owns retry); the OpenAI path wraps it in a transport-retry client.
ChatModel<ChatModelOptions> buildBackendChatModel(
  ModelBackendSpec spec, {
  required String model,
  List<Tool>? tools,
  http.Client? client,
}) {
  switch (spec) {
    case SwiftInferBackend s:
      return SwiftInferChatModel(
        name: model,
        baseUrl: s.baseUrl,
        bearerToken: s.bearerToken,
        headers: s.headers,
        tools: tools,
        client: client,
        defaultOptions: s.options,
      );
    case AnthropicBackend a:
      return AnthropicChatModel(
        name: model,
        apiKey: a.apiKey,
        baseUrl: a.baseUrl,
        headers: a.headers,
        tools: tools,
        client: client,
        enableThinking: a.enableThinking,
        defaultOptions: a.options,
      );
    case OpenAIBackend o:
      return OpenAIProvider(
        apiKey: o.apiKey,
        baseUrl: o.baseUrl,
        headers: o.headers ?? const {},
      ).createChatModel(
        name: model,
        tools: tools,
        enableThinking: o.enableThinking,
        temperature: o.temperature,
        options: o.options,
      );
  }
}
