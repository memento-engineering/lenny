# Spike go/no-go — dartantic_ai behind lenny's `ModelProvider` (lenny-7ey2)

**Verdict: GO on the API surface.** `dartantic_ai` 3.4.1 / `dartantic_interface`
4.0.0 satisfies all three non-negotiables on the swift-infer / Anthropic-wire
path. One **live smoke test remains** (creds-gated), and two caveats need a
decision in **lenny-4dhv**.

## Method

This spike environment has **no live creds** (`SWIFT_INFER_ENDPOINT` unset, no
frontier keys), so this is a **source-level + compile-level** proof against the
package resolved in the pub cache — not a live run. `bin/probe.dart` constructs
the real swift-infer wiring + a streaming consumer; it passes `dart analyze` and
`dart compile exe` **clean**. Clean compile == the public surface exists as
claimed. Live behavioral verification is the one open item (below).

## The three non-negotiables

### 1. Live thinking deltas — ✅ PASS
`ChatResult.thinking` (`String?`) carries **incremental reasoning deltas during
streaming**, separate from `output`; the consolidated reasoning lands as a
`ThinkingPart` in history. `AnthropicChatModel(enableThinking: true)`. Maps 1:1
onto lenny's `thinking()` → `ThinkingDelta` (DevTools thinking panel).

### 2. Custom baseUrl + headers — ✅ PASS
`AnthropicChatModel(baseUrl:, headers:, client:)` — point at swift-infer's `/v1`,
inject the bearer + `X-Conversation-Id` / `X-Session-Id` /
`X-Swift-Infer-Capture-Bodies` headers. `Provider.headers` semantics: **user
headers win on conflict** — matches swift-infer's "well-known set wins" intent.
OpenAI-wire endpoints are even simpler: `OpenAIProvider(baseUrl:, headers:)`.
*(Caveat A: the convenience `AnthropicProvider(...)` ctor hardcodes
`baseUrl: null` — so bind swift-infer at the `AnthropicChatModel` level or
subclass `Provider`.)*

### 3. Driver-owned retry — ✅ PASS on the Anthropic path
The Anthropic chat model uses the supplied `client` **directly — it does NOT wrap
it in `RetryHttpClient`** (the way the OpenAI path does). Hand it a plain client
→ the loop driver keeps full ownership of retry/timing.
*(Caveat C: the OpenAI path force-wraps `RetryHttpClient(maxRetries: 3)`. That
retry is **transport-only** — 429 / 5xx / IO exceptions — so it does **not**
re-sample on a `SchemaRejection` (a 200 with bad content), i.e. it does not break
lenny's decision-retry contract. It only removes driver control over transport
retries on the OpenAI adapter. Fix: upstream a `maxRetries` knob, or accept it.)*

### Bonus findings
- `sendStream(messages, {outputSchema})` — **structured-output is first-class**
  (lenny's `ActionSchema`).
- At the **ChatModel level**, `output` is a `ChatMessage` whose `parts` carry
  text **and tool-call parts** — the right granularity for `tool_use`
  accumulation. (The higher-level `Agent` API flattens `output` to a `String`;
  lenny should integrate at the ChatModel level.)
- The **runaway-think cap** stays a lenny stream-consumer behavior. dartantic
  offers `thinkingBudgetTokens` (Anthropic-native token budget) as a separate
  lever, not a replacement.

## Caveats to settle in lenny-4dhv

- **A — bind at ChatModel level** (provider ctor doesn't expose baseUrl). Minor.
- **B — Qwen sampling gap (MATERIAL).** `AnthropicChatOptions` has
  temperature / topP / topK / maxTokens / stopSequences but **no
  `presencePenalty` / `repetitionPenalty`**. lenny currently sends
  `presence_penalty: 1.5` + `repetition_penalty` to swift-infer for Qwen
  anti-repetition. Not expressible through dartantic's Anthropic options (real
  Anthropic has no such params). Options: (i) upstream PR adding extra body
  params, (ii) a swift-infer-specific `ChatModel` subclass, (iii) drop them and
  re-tune via temperature/topK + the loop's runaway cap. **Needs a live qwen
  A/B** to know if it actually degrades behavior.
- **C — OpenAI-path forced retry** (above).

## The one open item — live smoke test (creds-gated)

Confirm against a real endpoint with `SWIFT_INFER_ENDPOINT` +
`SWIFT_INFER_AGENT_TOKEN` (+ optionally `ANTHROPIC_API_KEY`):
1. thinking deltas actually stream through dartantic's Anthropic client **from
   swift-infer** (not just from api.anthropic.com);
2. tool-call parts accumulate into a usable `tool_use`;
3. qwen behaves acceptably **without** presence/repetition penalty (caveat B A/B).

## Recommendation

**GO → lenny-4dhv:** adopt dartantic behind the (collapsed) Anthropic-wire
provider, keep the loop's contracts, bind swift-infer at the ChatModel level, and
resolve caveat B with a live qwen A/B. Write the ratified **ADR 0003** there.

## Reproduce

```bash
cd spike/dartantic_probe
dart pub get
dart analyze bin/probe.dart      # -> No issues found!
dart compile exe bin/probe.dart  # -> compiles clean (no live call without creds)
```
