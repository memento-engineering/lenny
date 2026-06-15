/// Tighter defaults for hosted frontier models. PRD §16.4.
///
/// Consumed by `AnthropicModelProvider` and `OpenAiModelProvider`.
/// Frontier models warrant lower temperature, smaller observation budgets,
/// and tighter retry budgets versus the local Qwen3.6 path.
class FrontierDefaults {
  /// Sampling temperature.
  static const double temperature = 0.2;

  /// Maximum tokens per response.
  static const int maxTokens = 4096;

  /// Maximum bytes of observation context per turn.
  static const int maxObservationBytes = 6144;

  /// Maximum retries per turn (loop driver-owned).
  static const int maxRetries = 1;

  const FrontierDefaults._();
}
