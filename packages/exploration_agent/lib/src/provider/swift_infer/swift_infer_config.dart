/// Configuration for [SwiftInferModelProvider].
///
/// Sampling defaults are tuned for Qwen3.6-35B-A3B thinking mode per
/// PRD §16.3. Other MLX-served models will require different values.
///
/// Vision (`enableVision`) defaults to `false` until swift-infer's VLM
/// endpoint is verified end-to-end. When `false`, the provider strips
/// image content blocks from outgoing requests and reports
/// `ModelCapabilities.vision = false` so the loop driver (.18) can
/// skip screenshot capture without provider-specific branching.
class SwiftInferConfig {
  const SwiftInferConfig({
    required this.baseUrl,
    required this.model,
    this.apiKey,
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

  /// Optional API key forwarded as `x-api-key`. When `null`, the header
  /// is omitted entirely.
  final String? apiKey;

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
