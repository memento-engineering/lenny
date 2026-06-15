# ADR 0000 — AI decision register

**Status:** Living document — never Accepted, never closed.
**Rule (adopted from the_grid ADR-0000, Nico, 2026-06-11):** any decision made by AI lands here as an amendment and **stays here** until Nico promotes it (into its own ADR, or a named amendment of an existing one) or shoots it down. AI must not write its own decisions directly into ADR 0001+; those documents record human-ratified decisions only.

Entry format: `A<n> (date) — title` · Decision · Why · Affects · **Status:** pending | promoted → ⟨where⟩ | rejected.

**Substrate split (2026-06-11):** the substrate-level decisions from the founding conversation (schema-codegen, A2UI wire format, render backends, the projection/manipulation substrate) **moved to `engineering.memento/genesis` ADR-0000** (genesis A1–A8) when that repo was created — `perception` is migrating to genesis as a `tree` consumer. lenny's register now holds only **lenny-as-testing-harness** decisions. *(Note: ADR 0001/0002 — the perception design + migration — logically follow `perception` to genesis once the code physically moves; not done yet.)*

---

## A1 (2026-06-11) — Registration composes with the extension contract; catalog search parked

*(was A5; renumbered after the substrate entries migrated to genesis)*
**Decision:** node/catalog registration (genesis A2's codegen registry) must compose with lenny's **extension contract** — concretely the pure-Dart **`leonard_contract`** package (`extension.dart` / `types.dart` / `registry.dart` / `extension_context.dart`), the seam by which extensions contribute their own node vocabularies + schemas + `ext.exploration.*` surfaces. Retrieval/**search** over a large catalog (progressive-disclosure / RAG) is **parked** — eat the context now, optimize later.
**Why:** the catalog will be multi-extension and grow; registration is where extension vocabularies join genesis's codegen'd core registry. Search is real but premature; context budget is acceptable at current scale.
**On-disk reality (verified 2026-06-11):**
- the extension contract == the `leonard_contract` extraction — **bead `lenny-wisp-9h557`** (CODE_REVIEW), the_grid M0 prerequisite (the_grid ADR-0001 D6).
- the namespace rename `ext.flutter.exploration.*` → `ext.exploration.*` — **bead `lenny-wisp-41rdl`** (READY).
- the **package + terminology rename** (`leonard_*` → `leonard_*` and `extension` → `extension`): **bead `lenny-4tvb`** (P1, release blocker), created 2026-06-11.
**Affects (if promoted):** genesis A2's registry; `leonard_contract`'s `registry.dart`; the terminology sweep. **Status:** pending.

---

## A2 (2026-06-13) — Community-overlap finding: adopt Dart-team plumbing, keep the perception moat  ·  AI

**Finding + recommendation.** The `leonard_*` harness overlaps official Dart-team agent tooling in **plumbing only**.
**Duplication (3):** (1) **screenshots** — `leonard_flutter/lib/src/screenshot_extension.dart` hand-rolls `RenderView.layer.toImage` with an `invalid_use_of_protected_member` ignore; `ext.flutter.inspector.screenshot` does this over `vm_service`, no custom binding; (2) **transport** — hand-rolled `vm_service` discovery vs **DTD** (`dtd` 4.0.0, the canonical brokering substrate the official `dart_mcp_server` rides; lenny already deps `dtd` but only for filesystem); (3) the **running-app-agent concept** now has a first-party peer (`dart_mcp_server` 1.0.1: widget tree + runtime errors + screenshots + gestures + hot reload as MCP tools; our tool contract is already MCP-shaped).
**A gap, not duplication:** element tree + layout are free via `ext.flutter.inspector.getRootWidgetTree`/`getLayoutExplorerNode` — `inspect_widget_tool.dart` concedes element-tree access is "out of scope."
**The moat (no first-party equivalent — keep):** **semantics-FIRST perception** (we perceive the semantics tree = meaning, not the widget/inspector tree = dev structure — a deliberate, defensible divergence), **stability-gated observation** (`FrameStabilityTracker` / wait-for-settle), budgeted/curated/diffed agent-JSON, the **autonomous perception-action loop** (+ budgets, failure modes, trajectory), the extension contract (observation fragments + busy-state + 3-strike isolation).
**Recommendation:** adopt `ext.flutter.inspector.screenshot` (delete the hack); **ride DTD** for discovery; optionally add an element-tree/layout channel (keep semantics primary); **speak MCP at the boundary** as interop (tool shape already MCP-identical) so any MCP client drives a lenny-instrumented app + the loop can consume `dart_mcp_server` tools — without rewriting the loop; **keep the perception layer**. Maturity gate: inspector extensions + DTD are **mature → adopt now**; `dart_mcp`/`dart_mcp_server` are **experimental → track-and-align**. Credit: lenny already correctly adopted `devtools_extensions` + `vm_service`.
**Affects:** `leonard_flutter` (screenshot, transport, optional element-tree); `leonard_agent` (DTD discovery, MCP interop); the semantics-first stance (now `genesis_perception`). Beads `lenny-` (inspector-screenshot / DTD-discovery / MCP-interop). **Status:** pending.
