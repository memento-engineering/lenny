# ADR 0003 — Model backend: adopt dartantic; `ModelProvider` becomes a thin seam

- **Status:** Accepted (decision, 2026-06-16). Implementation tracked in `lenny-4dhv` + child beads.
- **Beads:** `lenny-4dhv` (end-state); `lenny-7ey2` (spike — GO, with live evidence).
- **Supersedes assumptions in:** the community-overlap finding [`docs/design/community-overlap-genkit.md`](../design/community-overlap-genkit.md).
- **Tagline:** *Adopt the wire and the primitives; keep the loop's contracts; custom-build only the backend that doesn't fit.*

## Context

`leonard_agent/lib/src/provider/` hand-rolls Genkit's core value proposition —
a unified model interface + tool-calling + structured output — in ~1.7k LOC
across three backends (Anthropic, OpenAI, swift-infer), plus a fourth copy of the
Anthropic wire (`swift_infer_provider.dart` ≈ `anthropic_provider.dart` + baseUrl
+ headers + Qwen sampling). The wire was never the value; the loop's contracts
were. We evaluated adopting an external Dart LLM abstraction instead of
maintaining this layer.

**Genkit Dart** is plugin-native and "correct," but Preview / `0.14` / pre-1.0
with TS-only plugin-authoring docs → track-and-align, not adopt (matches the
genesis A26 call against `a2ui_core`). **`dartantic_ai`** (`3.4.1`, post-1.0,
multi-provider, OpenAI-compat) is the credible adopt.

The spike (`lenny-7ey2`) proved at compile level that dartantic's surface covers
all three non-negotiables, and the **live test against swift-infer
(`qwen3.6-35b-a3b-8bit`)** then verified endpoint/auth/headers/**tool-calls**/
structured-output/retry on real traffic — and surfaced one swift-infer-specific
blocker on live thinking (below). Critically, dartantic is built on
**`genai_primitives`** (`ChatMessage`/`TextPart`/`ToolPart`/`ThinkingPart`) and
**`json_schema_builder`** (`Schema`/`S`) — the exact labs.flutter.dev packages
genesis A26 said to "adopt, don't invent." dartantic, genui, and genkit are
converging on these primitives.

## Decision

1. **Adopt `dartantic_ai` as lenny's model-backend substrate.** Its `ChatModel`
   contract, `Agent` orchestration, `genai_primitives` parts, and
   `json_schema_builder` schemas replace the hand-rolled provider wire. This
   closes the genesis **A26 item-4** gap (adopt `ToolDefinition`/parts rather
   than invent them).

2. **`ModelProvider` becomes a thin seam over dartantic, and a documented
   BYO-backend extension point.** The loop driver keeps `ModelProvider.decide()`
   and its contracts; the implementation delegates to a dartantic `ChatModel` /
   `Agent`. Frontier providers ship as **reference impls**, exactly like
   `leonard_router` / `leonard_riverpod` / `leonard_dio` are reference
   extensions. Third parties bring their own backend through the seam — *nobody
   installs the private swift-infer server; they plug in their own provider.*

3. **Frontier adapters (Anthropic, OpenAI) = stock dartantic.** Delete the
   hand-rolled Anthropic/OpenAI wire. Bind at the `ChatModel` level
   (`AnthropicChatModel(baseUrl:, headers:, client:)`) so the loop driver keeps
   retry ownership — the Anthropic path uses the supplied client directly (no
   `RetryHttpClient` wrap). Accept the OpenAI path's transport-only
   `RetryHttpClient` (it does not re-sample on a `SchemaRejection`), or upstream
   a `maxRetries` knob.

4. **swift-infer = a custom `ChatModel` on dartantic's interface** (the resolution
   of the live blocker; chosen over the cheaper server-side fix). It speaks
   swift-infer's Anthropic `/v1/messages` wire, parses thinking blocks **without
   requiring Anthropic's `signature`**, maps to `genai_primitives` parts, and
   carries the **Qwen sampling knobs** (`presence_penalty`, `repetition_penalty`)
   that `AnthropicChatOptions` cannot express. swift-infer stays untouched; lenny
   owns the backend that doesn't fit the stock options.

## Why the live test forced (4)

swift-infer streams real thinking blocks (`{"type":"thinking",...}`), but
`anthropic_sdk_dart` 1.5.0's `ThinkingBlock.fromJson` hard-casts
`signature: json['signature'] as String`. swift-infer/qwen omits Anthropic's
cryptographic signature → `Null is not a subtype of String`, **every turn**
(qwen emits thinking unconditionally, so `enableThinking: false` doesn't avoid
it). The OpenAI wire works for text+tools but dartantic refuses to surface
reasoning for Chat Completions. Two options were live:

- **(B, rejected as the primary fix)** emit `"signature": ""` from swift-infer —
  one line, but leaves the Qwen sampling gap unsolved and couples us to
  `anthropic_sdk_dart`'s strictness.
- **(A, chosen)** a custom swift-infer `ChatModel` — fixes the parse **and** the
  sampling gap in one move, and decouples the local backend from the SDK's
  evolving strictness. (B remains available as a quick smoke-validation shim.)

Frontier Claude is unaffected — real api.anthropic.com sends a `signature`.

## Contracts preserved (non-negotiable)

The loop owns these regardless of wire backing:

- **Live thinking deltas** → `ChatResult.thinking` → lenny `ThinkingDelta`.
- **Driver-owned retry** — providers throw `SchemaRejection`; no internal
  re-sample. (dartantic's transport retry is orthogonal; the Anthropic/custom
  path uses our client directly.)
- **Single-tool-per-turn + structured output** → `sendStream(outputSchema:)`.
- **Runaway-think cap** — a lenny stream-consumer behavior (dartantic's
  `thinkingBudgetTokens` is a separate token lever, not a replacement).

## Consequences

**Positive.** ~1.7k LOC of wire deleted; one configurable Anthropic path instead
of two; tool/part/schema vocabulary becomes the ecosystem-standard
`genai_primitives` + `json_schema_builder`; A26 item-4 closed; `ModelProvider`
becomes a real BYO-backend seam.

**Costs / risks.** New deps (`dartantic_ai`, transitively `anthropic_sdk_dart`,
`genai_primitives`, `json_schema_builder`) — all pre-1.0 except dartantic; pin
and watch. One custom `ChatModel` to own (swift-infer). dartantic baseUrl
**concatenates** `+ /v1/messages` → pass the bare origin on the Anthropic path
(documented footgun). OpenAI-path forced transport retry.

## Migration plan (decomposed into `lenny-4dhv` children)

1. **Custom swift-infer `ChatModel`** (keystone) — implement `ChatModel<…>` over
   swift-infer's Anthropic SSE: parse thinking blocks w/o `signature`, map to
   `genai_primitives` parts, carry Qwen sampling. Live-validate thinking + tools.
2. **Frontier adapters on stock dartantic** — Anthropic via `AnthropicChatModel`
   (baseUrl/headers/client), OpenAI via `OpenAIProvider`. Delete hand-rolled
   wire.
3. **`ModelProvider` seam** — re-express `decide()` over dartantic
   `ChatModel`/`Agent`; preserve `SchemaRejection` + thinking-stream + runaway
   cap; document the BYO-backend extension contract.
4. **Cutover + cleanup** — migrate the loop driver + CLI/DevTools provider
   registry; port/trim provider tests; remove `provider/{anthropic,openai,
   swift_infer}/*` hand-rolled wire.

## Alternatives considered

- **Genkit Dart** — plugin-native but Preview/pre-1.0, TS-only authoring docs →
  track-and-align.
- **Keep hand-rolled** — rejected; the wire is undifferentiated maintenance.
- **langchain.dart / dart_agent_core** — heavier framework / overlaps the loop;
  dartantic is the better-fit altitude.
