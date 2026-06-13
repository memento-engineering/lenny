# Community overlap: Dart/Flutter agent tooling vs. lenny's exploration harness

**Date:** 2026-06-13 · **Status:** findings + recommendation (register A2, pending Nico)

Assessment of whether lenny's `exploration_*` harness duplicates official
Dart/Flutter or Google-labs tooling, and what to adopt. The harness is an
"exploration agent" that introspects a running Flutter app — squarely the
territory the Dart team's MCP server, DTD, and widget-inspector now occupy.

**Headline: the duplication is real but narrow — it's all *plumbing*. The
product layer that makes lenny lenny has no first-party equivalent.** And one
finding is the opposite of duplication: a free capability lenny is *missing*.

## What lenny does today (map)

- **`exploration_flutter`** — a custom `ExplorationBinding extends
  WidgetsFlutterBinding`, running *in the real app* (debug/profile; release
  no-op). Capabilities, all exposed as `dart:developer` service extensions under
  `ext.flutter.exploration.*`: **semantics-tree capture** (its primary
  perception channel — *not* the widget/element tree), **screenshots**
  (`RenderView.layer.toImage`), layout geometry (from semantics rects),
  accessibility audit, a runtime-error ring buffer, **frame-stability tracking**,
  Navigator route-stack read, and **action tools** (tap/scroll/enter_text via
  `SemanticsAction` + synthesized pointers).
- **`exploration_agent`** — pure-Dart: the perception-action loop, tool-registry
  projection, observation diffing, model providers (swift-infer / Anthropic /
  OpenAI), trajectory JSONL, the `vm_service` client seam.
- **Plugin contract** — `ExplorationPlugin` + `ExplorationTool`
  (name + description + JSON `inputSchema` + `call`) registered into a
  `PluginRegistry`; each tool becomes a VM-service extension; observation
  fragments + busy-state + 3-strike isolation. **MCP-tool-shaped**, carried over
  `dart:developer` extensions rather than the MCP protocol.
- **`exploration_devtools`** — a real DevTools extension (correctly *adopts*
  `devtools_extensions` + `dtd`; DTD used only for filesystem persistence).
- **dio / riverpod / router** — reference plugins (Dio interceptor / Riverpod
  observer / Navigator-Router).
- **Transport** — raw `vm_service` end-to-end. No MCP, no DWDS, no `dart_mcp`.

## The official stack

| Thing | What it gives an agent | Maturity |
|---|---|---|
| **`WidgetInspectorService`** (`ext.flutter.inspector.*`) | Registered automatically in **debug** mode — no custom binding. Element/widget tree as `DiagnosticsNode` JSON (`getRootWidgetTree`), **layout/constraints** (`getLayoutExplorerNode`), **per-node screenshots** (`screenshot`), selection, properties — all over plain `vm_service`. | **Mature** (DevTools is built on it) |
| **`dart_mcp_server`** | 23 MCP tools incl. `widget_inspector` (get widget tree), `get_runtime_errors`, screenshots (via `flutter_driver_command`), gestures, `hot_reload` — driven by an external coding agent. | 1.0.1, **experimental** ("likely to evolve quickly") |
| **`dtd`** (Dart Tooling Daemon) | The canonical WebSocket/JSON-RPC brokering bus: discovers running apps' vm_service URIs, lets tools register/call services. The official MCP server rides it. | **4.0.0, stable** — the mature piece |
| `devtools_extensions` | Turnkey DevTools panel host (vm_service + DTD wired). lenny already uses it. | flutter.dev, ~0.5.1 |
| `integration_test` | Drive + introspect under a *test* harness (finders, screenshots). Overlaps *driving*, not live introspection. | Mature |

## Findings

**Duplication (plumbing lenny shouldn't have hand-rolled):**
1. **Screenshots.** `screenshot_extension.dart` reaches into `RenderView.layer.toImage(...)` behind the custom binding with an `invalid_use_of_protected_member` ignore. `ext.flutter.inspector.screenshot` already does this over `vm_service`, no custom binding, no hack.
2. **Transport/discovery.** lenny opens its own VM-service websocket + discovery; **DTD** is the canonical brokering substrate the official MCP server rides. lenny already deps `dtd ^4.0.0` but only for filesystem.
3. **The running-app-agent concept** now has a first-party peer in `dart_mcp_server`. lenny's tool contract is already MCP-shaped — the gap is just the protocol envelope.

**A gap (free capability lenny is *missing*, not duplicating):** `inspect_widget_tool.dart` returns only the semantics subtree, conceding element-tree access "requires `WidgetInspectorService` work that is out of scope." But `getRootWidgetTree` + `getLayoutExplorerNode` hand you the **element tree + layout, free, in any debug app**.

**The moat (no first-party equivalent — keep):**
- **Semantics-FIRST perception** — lenny perceives the *semantics* tree (meaning / what the app presents to assistive tech), not the widget/inspector tree (developer structure). A deliberate, defensible divergence aligned with the perception thesis. The official tools give the widget tree; this is a different axis.
- **Stability-gated observation** (`FrameStabilityTracker`, wait-for-settle) — the MCP tools are imperative one-shot RPCs with no settle concept.
- **Budgeted / curated / diffed agent-shaped JSON** vs the raw `DiagnosticsNode` firehose.
- **The autonomous perception-action loop** (budgets, failure modes, trajectory) — the MCP server is *driven* by an external agent, it isn't a loop.
- **The plugin contract** (observation fragments + busy-state + 3-strike isolation) — richer than plain MCP tools.

## Recommendation

- **Adopt `ext.flutter.inspector.screenshot`** — delete the hand-rolled
  `RenderView.layer.toImage` + protected-member ignore. Pure win.
- **Ride DTD** for app discovery/brokering instead of hand-rolled vm_service
  connection — the stable piece (4.0.0), the canonical substrate.
- **Optionally** add an element-tree/layout channel via
  `getRootWidgetTree`/`getLayoutExplorerNode` — but keep **semantics primary** by
  design.
- **Speak MCP at the boundary** as an interop surface (tool shape is already
  MCP-identical): let any MCP client drive a lenny-instrumented app, and let the
  loop consume `dart_mcp_server` tools — *without* rewriting the autonomous loop,
  which stays the product.
- **Keep the perception layer** — no first-party equivalent.

**Maturity gate:** the inspector extensions + DTD are **mature → adopt now**;
`dart_mcp` / `dart_mcp_server` are **experimental → track-and-align**, not a hard
dependency yet. Credit: lenny already correctly adopted `devtools_extensions` +
`vm_service`.

## Sources

lenny `packages/exploration_*` (read directly); docs.flutter.dev/ai/mcp-server;
pub.dev `dart_mcp` / `dart_mcp_server` / `dtd` / `devtools_extensions`; GitHub
`dart-lang/ai/pkgs/dart_mcp_server`; Flutter framework `widget_inspector.dart` +
`WidgetInspectorServiceExtensions`. Researched 2026-06-13.
