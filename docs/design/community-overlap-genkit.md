# Community overlap: Google's Genkit (Dart) vs. lenny's provider layer

**Date:** 2026-06-15 · **Status:** findings + recommendation — direction confirmed with Nico (2026-06-15). This is **not** an autonomous register entry: the call was made together, so it does not belong in `docs/adrs/0000` (the AI-decision register). The ratified **ADR 0003** gets written once the dartantic spike (lenny-7ey2) settles the structural end-state; until then this doc + the two beads carry it.

Assessment of whether lenny (and, secondarily, genesis) duplicated functionality
already shipping in Google's `genkit.dev` Dart packages, and whether we should
back our model-provider layer with a community package instead of hand-coding
each backend. Triggered by Nico pointing at
[`genkit`](https://pub.dev/packages/genkit),
[`genkit_middleware`](https://pub.dev/packages/genkit_middleware), and
[`schemantic`](https://pub.dev/packages/schemantic) — and the worry that
"no one is going to install my private swift-infer server."

This is the Genkit counterpart to the genesis `flutter/genui` analyses
(`engineering.memento/genesis/docs/design/community-overlap-{genui,consent}.md`,
genesis registers A26/A27). Genkit and genui are **sibling Google efforts**:
genui is the A2UI rendering stack (covered there); Genkit is the GenAI
orchestration framework (covered here).

## The deciding fact

**The overlap is one layer — the model-provider adapters in `leonard_agent` —
and it is ~5–10% of the codebase.** Genkit is server-side LLM orchestration; it
never touches a running app's frame lifecycle or semantics tree. lenny's whole
bet (perceive a *settled* app → decide → validate → act) and its loop contracts
have **no Genkit counterpart**. "Seems like a lot" is the adapter layer being
visible and annoying to maintain — not the system being a Genkit clone.

A second, sharper fact reframes the swift-infer question:
**swift-infer speaks the Anthropic `/v1/messages` wire.** Per
`swift_infer_provider.dart`, the provider is "essentially the frontier Anthropic
provider with a swift-infer base URL plus Qwen-tuned sampling." So swift-infer is
not a bespoke backend needing a bespoke plugin — it is *config on an
Anthropic-wire provider* (baseUrl + a handful of `X-` headers + a bearer token).

## What the three Genkit packages are

| Genkit pkg | What it does |
|---|---|
| `genkit` (`0.14.1`, **pre-1.0**, Dart=Preview) | GenAI orchestration: `ai.generate()`, `generateStream()`, `defineTool()`, `defineFlow()`, embeddings, remote actions, interrupts. Provider plugins: `genkit_anthropic` (`0.2.9`, 1 like), `genkit_openai`. |
| `schemantic` | General-purpose schema codegen: annotated abstract class → type-safe data class + runtime JSON Schema + validation (`$ref`, `@AnyOf` unions, BYO types). |
| `genkit_middleware` | Agent **harness** middleware: sandboxed filesystem ops, `SKILL.md` injection into the system prompt, tool-approval human-in-the-loop interrupts. |

## Overlap matrix

| Ours | Genkit | Verdict |
|---|---|---|
| `leonard_agent/lib/src/provider/` (`ModelProvider.decide`, `ToolDescriptor`, `ActionSchema`, anthropic/openai/swift_infer) | `genkit` + `genkit_anthropic` + `genkit_openai` + slice of `schemantic` | **Real overlap (~1.7k LOC).** Unified provider interface + tool-calling + structured output, re-treaded. `ToolDescriptor` is also identical to genui's `genai_primitives.ToolDefinition` (genesis A26 item 4). |
| `anthropic_provider.dart` ↔ `swift_infer_provider.dart` | — | **Internal duplication.** Two copies of the Anthropic `/v1/messages` wire; the second is the first + baseUrl + headers + Qwen sampling. |
| `genesis_taxonomy` schema emission | `schemantic` | **Mostly orthogonal.** Only the schema-emission + validation slice overlaps; the catalog→factory-registry codegen + `x-actions` affordance keyword have no `schemantic` counterpart. Same verdict as genesis A26's `json_schema_builder` call. |
| Claude Code / factory harness (skills, FS sandbox, approvals) | `genkit_middleware` | **Not our package code.** Overlaps the harness we *consume*, not lenny/genesis. Zero duplication to remove. |
| the perceive→decide→validate→act loop + stability policy + trajectory + extension contract | **none** | **The bet, unduplicated.** Genkit is server-side; it has no frame lifecycle, no semantics tree, no VM-service hook, no stability gate. |

We duplicated **one layer** — the model-provider wire — not the system.

## "Would Genkit support a swift-infer plugin?"

Yes — but you would not write a plugin, and Genkit isn't the safe place to land
it:

1. **Genkit is explicitly plugin-based.** Custom backends register via
   `ai.defineModel({name, supports, configSchema}, request => …)` — exactly the
   extension shape the question reaches for. A `genkitx-swift-infer` plugin is
   the supported pattern.
2. **You likely don't need a plugin at all.** Because swift-infer is
   Anthropic-compatible, a *baseUrl + headers override on an Anthropic provider*
   suffices — config, not code. The blocker: `genkit_anthropic`'s docs show **no
   baseUrl/headers override**. If that override doesn't exist, you're forced back
   into authoring a plugin.
3. **The risk:** Dart Genkit is **Preview / `0.14.1` / pre-1.0**, and
   plugin-authoring is documented for **TypeScript only**. You'd be pioneering
   the Dart custom-model path on a moving SDK. Same instability call we already
   made against `a2ui_core` (genesis A26).

## Other backend abstractions on pub (surveyed 2026-06-15)

| Package | Maturity | Fit for swift-infer | Note |
|---|---|---|---|
| **`dartantic_ai`** | **`3.4.1`, post-1.0**, 58 likes, 8k dl, verified pub | **Best candidate.** Multi-provider (OpenAI/Anthropic/Google/Mistral/Ollama/OpenRouter/xAI) + explicit **OpenAI-compat passthrough** | The credible "adopt the wire." Post-1.0 beats Genkit's 0.14. |
| `genkit` + `genkit_anthropic` | `0.14.1` / `0.2.9`, pre-1.0, 1 like | Plugin via `defineModel`, or baseUrl if exposed (unconfirmed) | Google-blessed, plugin-native, but Dart=Preview, TS-only plugin docs |
| `langchain.dart` (`langchain_anthropic`/`_openai`) | Mature, widely used | ChatOpenAI/ChatAnthropic generally take baseUrl overrides | Heavy framework surface for what we need |
| `dart_agent_core` | Newer | Unified `LLMClient` (OpenAI/Gemini/Bedrock) | It's an *agent loop* too — overlaps our loop, not just the wire |
| `flutter_ai_toolkit` | Google/Flutter team | Abstract provider API, Firebase-leaning, Flutter-coupled | Wrong altitude (UI toolkit) |

## The non-negotiables any external backing must honor

The provider layer's value was never the HTTP — it was the loop's contracts.
Any adopted wire library must expose enough control to keep all of these, or we
lose capability:

1. **Live reasoning/thinking deltas** — `<think>…</think>` chunks surface on the
   `thinking()` stream for the DevTools thinking panel.
2. **Driver-owned retry** — providers throw `SchemaRejection` and **must not
   retry internally**; the loop driver owns retry policy (one retry with the
   validation error injected back).
3. **Custom per-request headers + baseUrl** — swift-infer needs a base URL, a
   bearer token, and `X-Conversation-Id` / `X-Session-Id` /
   `X-Swift-Infer-Capture-Bodies` for gateway-side capture/telemetry.
4. (Bonus) the **runaway-think cap** — abort a qwen turn that ruminates past
   ~8k chars without committing to a `tool_use`.

## Recommendation — make `ModelProvider` a real extension seam; back the wire, keep the loop

Not "port to Genkit." Three steps, in order:

1. **Now, no dependency:** collapse `anthropic_provider.dart` (303 LOC) +
   `swift_infer_provider.dart` (369 LOC) into **one configurable Anthropic-wire
   provider**, so swift-infer becomes *config, not a class*. This is the most
   duplicated code and is an internal refactor worth doing regardless. → part of
   **lenny-4dhv**.
2. **Make `ModelProvider` a documented BYO-backend extension point** — frontier
   providers ship as reference impls, exactly like `leonard_router` /
   `leonard_riverpod` / `leonard_dio` are reference extensions. This is the
   answer to "no one installs my private server": nobody *should* — they plug in
   their own provider through the seam. → **lenny-4dhv**.
3. **Spike `dartantic_ai` (not Genkit) behind the 2 frontier adapters.** It's
   post-1.0 and OpenAI-compat. The make-or-break test is the four
   non-negotiables above. If it passes, the adapters become thin shims and we
   maintain almost no wire code. If it can't surface thinking deltas / honor
   no-internal-retry / pass custom headers, keep native — the value was the
   contract. → **lenny-7ey2** (do first; **lenny-4dhv** is blocked on it).

**Genkit stays "track-and-align"** — revisit when Dart Genkit leaves Preview and
`genkit_anthropic` documents a baseUrl override. Betting the backend on a Preview
SDK whose Dart plugin path we'd be inventing is the same instability call genesis
A26 already made against `a2ui_core`.

## Beads

- **lenny-7ey2** — Spike: back `ModelProvider` frontier adapters with
  `dartantic_ai` (do first).
- **lenny-4dhv** — Decide provider-layer end state: collapse Anthropic/swift-infer
  + adopt-vs-keep wire lib (blocked on lenny-7ey2).

## Sources

pub.dev pages + version histories for `genkit` (`0.14.1`), `genkit_anthropic`
(`0.2.9`), `schemantic`, `genkit_middleware`, `dartantic_ai` (`3.4.1`),
`langchain.dart`, `dart_agent_core`, `flutter_ai_toolkit`;
`genkit.dev/docs/plugin-authoring/overview/` (`defineModel`). lenny source:
`leonard_agent/lib/src/provider/{model_provider,types,action_schema}.dart`,
`.../swift_infer/{swift_infer_config,swift_infer_provider}.dart`. Prior analyses:
genesis `community-overlap-{genui,consent}.md` (registers A26/A27); lenny register
A2. Researched 2026-06-15.
