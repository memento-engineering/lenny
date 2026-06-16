# ADR 0000 — AI decision register

**Status:** Living document — never Accepted, never closed.
**Rule (Nico, 2026-06-11):** any decision made by AI lands here as an amendment and **stays here** until Nico promotes it (into its own ADR, or a named amendment of an existing one) or shoots it down. AI must not write its own decisions directly into ADR 0001+; those documents record human-ratified decisions only.

Entry format: `A<n> (date) — title` · Decision · Why · Affects · **Status:** pending | promoted → ⟨where⟩ | rejected.

**Substrate split (2026-06-11):** the substrate-level decisions from the founding conversation (schema-codegen, A2UI wire format, render backends, the projection/manipulation substrate) **moved to `engineering.memento/genesis` ADR-0000** (genesis A1–A8) when that repo was created — `perception` is migrating to genesis as a `tree` consumer. lenny's register now holds only **lenny-as-testing-harness** decisions. *(Note: ADR 0001/0002 — the perception design + migration — logically follow `perception` to genesis once the code physically moves; not done yet.)*

---

## A1 (2026-06-11) — Registration composes with the extension contract; catalog search parked

*(was A5; renumbered after the substrate entries migrated to genesis)*
**Decision:** node/catalog registration (genesis A2's codegen registry) must compose with lenny's **extension contract** — concretely the pure-Dart **`leonard_contract`** package (`extension.dart` / `types.dart` / `registry.dart` / `extension_context.dart`), the seam by which extensions contribute their own node vocabularies + schemas + `ext.exploration.*` surfaces. Retrieval/**search** over a large catalog (progressive-disclosure / RAG) is **parked** — eat the context now, optimize later.
**Why:** the catalog will be multi-extension and grow; registration is where extension vocabularies join genesis's codegen'd core registry. Search is real but premature; context budget is acceptable at current scale.
**On-disk reality:**
- the extension contract is the `leonard_contract` extraction.
- the namespace rename `ext.flutter.exploration.*` → `ext.exploration.*`.
- the package + terminology rename to the `leonard_*` packages and `extension` terminology — completed.
**Affects (if promoted):** genesis A2's registry; `leonard_contract`'s `registry.dart`. **Status:** pending.

---

## A2 (2026-06-13) — Community-overlap finding: adopt Dart-team plumbing, keep the perception moat  ·  AI

**Finding + recommendation.** The `leonard_*` harness overlaps official Dart-team agent tooling in **plumbing only**.
**Duplication (3):** (1) **screenshots** — `leonard_flutter/lib/src/screenshot_extension.dart` hand-rolls `RenderView.layer.toImage` with an `invalid_use_of_protected_member` ignore; `ext.flutter.inspector.screenshot` does this over `vm_service`, no custom binding; (2) **transport** — hand-rolled `vm_service` discovery vs **DTD** (`dtd` 4.0.0, the canonical brokering substrate the official `dart_mcp_server` rides; lenny already deps `dtd` but only for filesystem); (3) the **running-app-agent concept** now has a first-party peer (`dart_mcp_server` 1.0.1: widget tree + runtime errors + screenshots + gestures + hot reload as MCP tools; our tool contract is already MCP-shaped).
**A gap, not duplication:** element tree + layout are free via `ext.flutter.inspector.getRootWidgetTree`/`getLayoutExplorerNode` — `inspect_widget_tool.dart` concedes element-tree access is "out of scope."
**The moat (no first-party equivalent — keep):** **semantics-FIRST perception** (we perceive the semantics tree = meaning, not the widget/inspector tree = dev structure — a deliberate, defensible divergence), **stability-gated observation** (`FrameStabilityTracker` / wait-for-settle), budgeted/curated/diffed agent-JSON, the **autonomous perception-action loop** (+ budgets, failure modes, trajectory), the extension contract (observation fragments + busy-state + 3-strike isolation).
**Recommendation:** adopt `ext.flutter.inspector.screenshot` (delete the hack); **ride DTD** for discovery; optionally add an element-tree/layout channel (keep semantics primary); **speak MCP at the boundary** as interop (tool shape already MCP-identical) so any MCP client drives a lenny-instrumented app + the loop can consume `dart_mcp_server` tools — without rewriting the loop; **keep the perception layer**. Maturity gate: inspector extensions + DTD are **mature → adopt now**; `dart_mcp`/`dart_mcp_server` are **experimental → track-and-align**. Credit: lenny already correctly adopted `devtools_extensions` + `vm_service`.
**Affects:** `leonard_flutter` (screenshot, transport, optional element-tree); `leonard_agent` (DTD discovery, MCP interop); the semantics-first stance (now `genesis_perception`). **Status:** pending.

---

## A3 (2026-06-15) — Community-overlap finding: the provider layer re-treads Genkit; back the wire, keep the loop  ·  AI

**Finding + recommendation.** Triggered by Nico pointing at Google's `genkit.dev` packages (`genkit`, `genkit_anthropic`/`genkit_openai`, `schemantic`, `genkit_middleware`). Full analysis: [`docs/design/community-overlap-genkit.md`](../design/community-overlap-genkit.md).
**Duplication (one layer, ~1.7k LOC).** `leonard_agent/lib/src/provider/` hand-rolls Genkit's core value prop — unified model interface + tool-calling + structured output: `ModelProvider.decide()` ≈ `ai.generate()`; `ToolDescriptor{name,description,inputSchema}` ≈ Genkit/`genai_primitives` `ToolDefinition`; `anthropic_provider.dart` ≈ `genkit_anthropic`; `openai/*` ≈ `genkit_openai`; `ActionSchema` + the `json_schema` dep ≈ a sliver of `schemantic`. **Internal** duplication too: `swift_infer_provider.dart` is `anthropic_provider.dart` + a base URL + headers + Qwen sampling (swift-infer speaks the **Anthropic `/v1/messages` wire**) — two copies of one wire.
**Not duplicated.** `genkit_middleware` (SKILL.md injection / sandboxed FS / tool-approval interrupts) overlaps the **Claude Code / factory harness we consume**, not lenny/genesis package code. `schemantic` vs `genesis_taxonomy`: only the schema-emission slice overlaps; the catalog→factory-registry codegen + `x-actions` affordances are ours (same verdict as the genui `json_schema_builder` analysis, genesis A26).
**The moat (no Genkit equivalent — keep).** Genkit is server-side orchestration; it never touches a live app's frame lifecycle / semantics tree. lenny's perceive→decide→validate→act loop and its contracts (single-tool-per-turn, **driver-owned retry** / providers MUST NOT retry internally, runaway-think cap, live `<think>` stream) have no counterpart. The value of the provider layer was never the HTTP — it was the contract.
**Recommendation.** Don't port to Genkit (Dart=Preview/`0.14`/pre-1.0; plugin authoring TS-only; `genkit_anthropic` shows no baseUrl override → high-ceiling/high-risk; track-and-align). Instead: (1) **spike `dartantic_ai`** (`3.4.1`, post-1.0, multi-provider + OpenAI-compat) behind the 2 frontier adapters — go/no-go on the 3 non-negotiables (thinking deltas / no internal retry / custom headers+baseUrl) → **lenny-7ey2**; (2) **collapse the two Anthropic-wire providers into one configurable provider** (swift-infer = config, not a class) and make `ModelProvider` a documented **BYO-backend extension seam** (same pattern as `leonard_router`/`riverpod`/`dio`) → **lenny-4dhv** (blocked on the spike). swift-infer should never ship as someone else's dependency — third parties bring their own provider through the seam.
**Affects:** `leonard_agent/lib/src/provider/*` (adapter consolidation + optional dartantic backing); the `ModelProvider` extension contract; `genesis_taxonomy` (schema-emission slice only, optional). **Status:** pending.
