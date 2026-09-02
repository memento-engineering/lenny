---
status: accepted
date: 2026-06-13
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a2-community-overlap-finding-adopt-dart-team-plumbing-keep-t
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A2"
---
## A2 (2026-06-13) — Community-overlap finding: adopt Dart-team plumbing, keep the perception moat  ·  AI

**Finding + recommendation.** The `leonard_*` harness overlaps official Dart-team agent tooling in **plumbing only**.
**Duplication (3):** (1) **screenshots** — `leonard_flutter/lib/src/screenshot_extension.dart` hand-rolls `RenderView.layer.toImage` with an `invalid_use_of_protected_member` ignore; `ext.flutter.inspector.screenshot` does this over `vm_service`, no custom binding; (2) **transport** — hand-rolled `vm_service` discovery vs **DTD** (`dtd` 4.0.0, the canonical brokering substrate the official `dart_mcp_server` rides; lenny already deps `dtd` but only for filesystem); (3) the **running-app-agent concept** now has a first-party peer (`dart_mcp_server` 1.0.1: widget tree + runtime errors + screenshots + gestures + hot reload as MCP tools; our tool contract is already MCP-shaped).
**A gap, not duplication:** element tree + layout are free via `ext.flutter.inspector.getRootWidgetTree`/`getLayoutExplorerNode` — `inspect_widget_tool.dart` concedes element-tree access is "out of scope."
**The moat (no first-party equivalent — keep):** **semantics-FIRST perception** (we perceive the semantics tree = meaning, not the widget/inspector tree = dev structure — a deliberate, defensible divergence), **stability-gated observation** (`FrameStabilityTracker` / wait-for-settle), budgeted/curated/diffed agent-JSON, the **autonomous perception-action loop** (+ budgets, failure modes, trajectory), the extension contract (observation fragments + busy-state + 3-strike isolation).
**Recommendation:** adopt `ext.flutter.inspector.screenshot` (delete the hack); **ride DTD** for discovery; optionally add an element-tree/layout channel (keep semantics primary); **speak MCP at the boundary** as interop (tool shape already MCP-identical) so any MCP client drives a lenny-instrumented app + the loop can consume `dart_mcp_server` tools — without rewriting the loop; **keep the perception layer**. Maturity gate: inspector extensions + DTD are **mature → adopt now**; `dart_mcp`/`dart_mcp_server` are **experimental → track-and-align**. Credit: lenny already correctly adopted `devtools_extensions` + `vm_service`.
**Affects:** `leonard_flutter` (screenshot, transport, optional element-tree); `leonard_agent` (DTD discovery, MCP interop); the semantics-first stance (now `genesis_perception`). **Status:** pending.

---

