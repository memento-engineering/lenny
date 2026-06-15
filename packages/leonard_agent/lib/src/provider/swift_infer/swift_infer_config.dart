/// Configuration for [SwiftInferModelProvider].
///
/// Sampling defaults are tuned for Qwen3.6-35B-A3B thinking mode per
/// PRD §16.3. Other MLX-served models will require different values.
///
/// Vision (`enableVision`) defaults to `false` until swift-infer's VLM
/// endpoint is verified end-to-end. When `false`, the provider strips
/// image content blocks from outgoing requests and reports
/// `ModelCapabilities.vision = false` so the loop driver can
/// skip screenshot capture without provider-specific branching.
///
/// Wire-contract parity with `fs agent` (factoryskills' agent
/// implementation in `factoryskills/internal/agent/agent.go`):
///   * `bearerToken` → `Authorization: Bearer <token>` (matches
///     `SWIFT_INFER_AGENT_TOKEN`).
///   * `captureBodies` → `X-Swift-Infer-Capture-Bodies: true`.
///   * `conversationId` → `X-Conversation-Id: <value>`.
///   * `sessionId` → `X-Session-Id: <value>`.
///   * `extraHeaders` is merged into outgoing requests for forward-compat
///     and per-deployment customisation. Entries cannot overwrite the
///     four well-known headers above, nor `Content-Type`,
///     `Accept`, or `anthropic-version` — the well-known set always
///     wins on conflict (provider asserts this precedence).
class SwiftInferConfig {
  const SwiftInferConfig({
    required this.baseUrl,
    required this.model,
    this.bearerToken,
    this.captureBodies = false,
    this.conversationId,
    this.sessionId,
    this.extraHeaders = const <String, String>{},
    this.enableVision = false,
    this.temperature = 1.0,
    this.topP = 0.95,
    this.topK = 20,
    this.presencePenalty = 1.5,
    this.repetitionPenalty = 1.0,
    this.preserveThinking = true,
    this.maxTokens = 4096,
  });

  /// Base URL of the swift-infer gateway (e.g. `http://localhost:8080`).
  final Uri baseUrl;

  /// MLX model id served by swift-infer (e.g. `qwen3.6-35b-a3b-8bit`).
  final String model;

  /// Forwarded as `Authorization: Bearer <token>`. Mirrors `fs agent`'s
  /// `SWIFT_INFER_AGENT_TOKEN`. When `null` or empty, the header is
  /// omitted entirely (unauthenticated request).
  final String? bearerToken;

  /// When `true`, sends `X-Swift-Infer-Capture-Bodies: true` so the
  /// gateway captures the request and response bodies for inspection
  /// via `GET /v1/conversations/<id>`.
  final bool captureBodies;

  /// Forwarded as `X-Conversation-Id` when non-null. Lets the gateway
  /// group every turn of one exploration run for inspection.
  final String? conversationId;

  /// Forwarded as `X-Session-Id` when non-null.
  final String? sessionId;

  /// Forward-compat header bag. Merged into outgoing requests *first*;
  /// the provider then sets the well-known headers (Content-Type,
  /// Accept, anthropic-version, Authorization,
  /// X-Swift-Infer-Capture-Bodies, X-Conversation-Id, X-Session-Id) on
  /// top so they always win on conflict.
  final Map<String, String> extraHeaders;

  /// When `false`, image blocks are stripped from outgoing messages and
  /// `ModelCapabilities.vision` is reported as `false`.
  final bool enableVision;

  /// Sampling temperature.
  final double temperature;

  /// Nucleus-sampling top-p.
  final double topP;

  /// Top-k sampling cutoff.
  final int topK;

  /// Presence penalty applied to repeated tokens.
  final double presencePenalty;

  /// Repetition penalty.
  final double repetitionPenalty;

  /// Whether `<think>...</think>` reasoning is preserved across turns.
  final bool preserveThinking;

  /// Maximum tokens in a single response.
  final int maxTokens;
}
