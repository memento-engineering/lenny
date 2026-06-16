// Spike probe for lenny-7ey2 — does dartantic_ai (3.4.1) satisfy lenny's three
// ModelProvider non-negotiables? This file is COMPILE-LEVEL proof: it exercises
// the real public API surface. It is not run live (this env has no creds); the
// live smoke test is a creds-gated follow-up.
//
//   (1) live thinking/reasoning deltas, separate from answer text
//   (2) custom baseUrl + custom headers (swift-infer is Anthropic-wire)
//   (3) driver-owned retry — provider must NOT retry internally
//
// `dart analyze` clean == the surface exists as claimed.
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:http/http.dart' as http;

/// A pass-through client with NO retry. Because the Anthropic chat model uses
/// the supplied client *directly* (it does not wrap it in RetryHttpClient, the
/// way the OpenAI path does), handing it this client means the loop driver keeps
/// full ownership of retry/timing — non-negotiable (3) on the swift-infer path.
class DirectClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);
  @override
  void close() => _inner.close();
}

/// swift-infer speaks the Anthropic `/v1/messages` wire, so we bind at the
/// AnthropicChatModel level (the convenience `AnthropicProvider(...)` hardcodes
/// baseUrl=null — caveat A). This single constructor call proves (2) and (3).
AnthropicChatModel buildSwiftInferModel() => AnthropicChatModel(
  name: 'qwen3.6-35b-a3b-8bit',
  apiKey: 'swift-infer-bearer-token', // (2) auth
  baseUrl: Uri.parse('http://localhost:8080/v1'), // (2) custom endpoint
  enableThinking: true, // (1) reasoning on
  client: DirectClient(), // (3) no internal retry
  headers: const <String, String>{
    // (2) per-session swift-infer telemetry headers — user headers win on
    // conflict per Provider.headers semantics.
    'X-Conversation-Id': 'run-123',
    'X-Session-Id': 'sess-123',
    'X-Swift-Infer-Capture-Bodies': 'true',
  },
  defaultOptions: AnthropicChatOptions(
    temperature: 1.0,
    topP: 0.95,
    topK: 20,
    maxTokens: 4096,
    // CAVEAT B: no presencePenalty / repetitionPenalty here. lenny currently
    // sends presence_penalty=1.5 + repetition_penalty to swift-infer for Qwen;
    // AnthropicChatOptions cannot express them (real Anthropic has no such
    // params). Would need an upstream options extension or a custom ChatModel.
  ),
);

/// Proves (1): `ChatResult.thinking` carries incremental reasoning deltas while
/// streaming, distinct from `ChatResult.output` (the answer / tool text). Maps
/// 1:1 onto lenny's `thinking()` stream → `ThinkingDelta`. `sendStream` also
/// accepts an `outputSchema` — that is lenny's structured-output / ActionSchema
/// constraint, first-class.
Future<void> consumeStream(AnthropicChatModel model, Schema? actionSchema) async {
  final Stream<ChatResult<ChatMessage>> stream = model.sendStream(
    const <ChatMessage>[],
    outputSchema: actionSchema, // structured output / tool constraint
  );
  await for (final ChatResult<ChatMessage> chunk in stream) {
    if (chunk.thinking != null) {
      // → lenny ThinkingDelta (DevTools thinking panel)
    }
    // At the ChatModel level (vs the higher-level Agent API where output is a
    // String), `output` is a ChatMessage whose `parts` carry text AND tool-call
    // parts — exactly what lenny needs to accumulate a tool_use. Good fit.
    final ChatMessage delta = chunk.output;
    if (delta.parts.isEmpty) continue;
    // → lenny assistant turn / tool-call accumulation
  }
}

/// Proves the OpenAI-compatible path: `OpenAIProvider` exposes baseUrl + headers
/// directly, so any OpenAI-wire endpoint is config, not code.
OpenAIProvider buildOpenAICompat() => OpenAIProvider(
  baseUrl: Uri.parse('https://my-openai-compatible-host/v1'),
  headers: const <String, String>{'Authorization': 'Bearer token'},
);

void main() {
  // Compile-only. Construct everything to force the analyzer through the real
  // signatures; do not hit the network (no creds in this environment).
  final model = buildSwiftInferModel();
  // ignore: discarded_futures
  consumeStream(model, null);
  buildOpenAICompat();
}
