# Flutter Exploration Agent — PRD

**Status:** Draft v0.5
**Author:** Nico
**Last updated:** 2026-05-07

**Changes from v0.4:**
- Added a DevTools extension as a v1 deliverable. Provides prompt entry, live thinking-trace streaming, and an interactive session timeline. Built on `package:devtools_extensions`. New §6.3 in architecture, expanded §18 (v1 scope), new success criterion in §23.
- Refactored the harness/frontend boundary. The harness loop is now a library, consumed by two frontends in v1: a CLI (no UI, scriptable) and a DevTools extension panel (UI-rich, in-IDE). Same harness, same binding, two surfaces.

**Changes from v0.3:**
- Replaced `go_router` with raw `Router`/`Navigator` as the routing reference plugin. Simpler, exercises the contract more honestly, no opinionated framework dependency.
- Updated §16 (model integration) for Qwen3.6-35B-A3B specifics: vision-language model so screenshots default on, `qwen3_coder` tool-call parser requirement, `preserve_thinking` support, recommended sampling parameters.
- Added a pre-build verification step for `mlx-vlm` tool-call parser support.
- Aligned plugin discovery convention with the emerging Dart `extension/` pattern from Jake MacDonald's "Packaged AI Assets" proposal (extension/exploration/config.yaml). Implementation still uses explicit registration in v1, but the convention is in place for future auto-discovery.
- Added a new §8 on resources and prompts as a deferred plugin contract extension, mirroring the MCP Resources/Prompts shape from the Packaged AI Assets design.
- Clarified that plugin updates are not breaking changes (consistent with the Packaged AI Assets posture).
- Removed the deprecation-warnings open question.

**Changes from v0.2:** Restructured around a host-and-plugins architecture. The host binding is small and policy-free; plugins contribute tools, observations, and lifecycle hooks via a typed Dart contract built on the VM service extension protocol. This reframes the Navigator 2.0 problem as a routing-plugin concern rather than a core-binding problem, and creates a path for third-party packages (state management, networking, custom design systems, even Marionette itself) to integrate without forking the project.

---

## 1. Summary

A Dart-based agent harness that drives a running Flutter application through a custom `WidgetsBinding`. The binding is small and opinionated about almost nothing: it registers a plugin contract on top of the VM service extension protocol, coordinates the perception-action loop, and gets out of the way. Tools, observation fragments, and lifecycle hooks come from plugins.

The harness operates against the *real running app*, not a test entrypoint. Real network, real time, real animations. Stability is defined by the harness using observable frame-lifecycle signals plus plugin-contributed busy-state, not by `pumpAndSettle`.

The deliverable is the perception-action primitive plus the plugin contract. The interesting capabilities — routing-aware navigation, state-graph observation, network-aware stability — come from plugins, written by us for v1 and by the ecosystem over time.

## 2. Motivation

Browser automation agents have a chronic problem: they don't know when their actions complete. Every observation is a snapshot of indeterminate freshness, and a large fraction of failures are races against animations, network calls, or partial renders.

Flutter is structurally different. The framework's `SchedulerBinding` exposes the frame lifecycle directly. The semantics tree exposes interactable elements at a screen-reader level of abstraction. The VM service extension protocol (`registerExtension` from `dart:developer`) is a publicly available extensibility surface that any package in the running app can register handlers against. Combined, this gives us an environment where an LLM-driven agent can operate with native temporal grounding, structured observations, and a path for ecosystem extensibility.

Existing tools in this space (the official Dart MCP server, Marionette MCP) make a different tradeoff: they are opinionated, monolithic, and intentionally small in scope. They are good at what they do. This project takes a different bet: that the agent loop is general but the things it needs to know about a specific app are not, and that the ecosystem will produce better integrations for `go_router`, Riverpod, Dio, Sentry, Firebase, and the rest than any single project could ship and maintain. The host's job is to be a good plugin host. The plugins' job is to know about specific things.

## 3. Goals & non-goals

### Goals

- Provide a perception-action loop where one turn corresponds to one stable observation of the running app, with stability defined by the harness plus plugin-contributed busy-state.
- Provide a typed plugin contract that lets third-party packages contribute tools, observation fragments, and lifecycle hooks without forking the host.
- Keep the host binding small enough that its conceptual surface fits in a single document.
- Validate proposed actions against the live observation before execution to keep local-model errors from costing full turns.
- Maintain two distinct forms of session memory: a *running summary* authored by the model, and a *per-turn diff* authored by the harness.
- Support pluggable model backends, with first-class support for a local MLX-served Qwen3.6-35B-A3B and frontier APIs as fallback.
- Run on every platform the target Flutter app runs on, including web and desktop.
- Ship with reference plugins that demonstrate the contract and solve concrete problems (routing, state, networking).

### Non-goals

- Generating new Flutter code, including new tests. The agent only acts on the running app.
- Replacing the Dart MCP server or Marionette MCP. Those are for IDE-side workflows; this is for harness work where the user controls the loop end to end. (A plugin that exposes Marionette-equivalent functionality is in scope; replacing Marionette is not.)
- Self-improving training loops, RL, or fine-tuning pipelines. Trajectory collection is in scope; what's done with the trajectories is downstream.
- General-purpose mobile UI testing across React Native, native iOS, native Android. Flutter only.
- Running against a release-mode app. The harness depends on debug-mode VM service extensions.
- Solving every routing/state/networking framework. We solve the contract; plugins solve the framework-specific bits.

## 4. Target users

- **Flutter developers** running exploration sessions against their own apps to find broken flows, dead routes, or accessibility gaps.
- **QA and reliability engineers** running long-form exploration sweeps and capturing trajectories for review.
- **Researchers and tinkerers** collecting (observation, action) trajectories for downstream work.
- **Plugin authors** — package maintainers (routing libraries, state management, design systems) who want their package to be visible to and controllable by the exploration agent.

The first audience shapes the host. The plugin authors shape the ecosystem.

## 5. Concepts and terminology

**Host.** The core binding plus the harness. Owns the perception-action loop, stability policy, action validation, trajectory log. Knows nothing about specific routing, state, or networking libraries.

**Plugin.** A Dart package that implements the plugin contract (§7). Contributes some combination of tools, observation fragments, and lifecycle hooks. Lives in the user's app.

**Turn.** One iteration of the perception-action loop.

**Stability policy.** The host's rule for when to capture an observation. Considers framework signals (transient callbacks, microtasks) and plugin-contributed busy-state.

**Observation.** The host's snapshot of the app at a turn boundary. A merged structure: core fragment (semantics tree, route stack, errors, stability metadata) plus plugin-contributed fragments.

**Action.** A typed call to a tool. Some tools come from the host (semantics-tree-driven tap, enter_text, scroll, screenshot); most come from plugins.

**Diff.** Mechanical, host-authored description of what changed between observations. Per-turn, includes plugin-contributed fragments.

**Running summary.** Narrative, model-authored description of the agent's accumulated knowledge. Updated each turn.

**Trajectory.** The full sequence of (observation, action, diff, summary) tuples plus session metadata.

**Goal.** The user-provided objective for the session.

## 6. Architecture

### 6.1 The host binding (`exploration_flutter`)

A Dart package the user adds to their Flutter app. Provides `ExplorationBinding extends WidgetsFlutterBinding`, initialized in `main()` with `kDebugMode` gating. The recommended entry point is `ExplorationBinding.run(ExplorationApp)`, which claims the `WidgetsBinding` slot before any user code constructs Flutter-aware objects (e.g. `GoRouter`, `MaterialApp`). The lower-level `ensureInitialized(plugins:)` surface remains for tests and headless agents that own ordering. The binding:

- Replaces the default `WidgetsBinding`. Conflicts with `IntegrationTestWidgetsFlutterBinding` and other custom bindings; only one binding per process.
- Registers a small set of *core* VM service extensions for the perception-action primitives the host owns.
- Hosts a plugin registry. Plugins register with the binding at initialization time.
- Exposes a `getStableObservation(policy)` extension that merges the core fragment with plugin-contributed fragments.
- Hooks into `SchedulerBinding` to track transient callbacks, microtasks, and frame commits.
- Maintains a bounded ring buffer of recent runtime errors via `FlutterError.onError` and `PlatformDispatcher.instance.onError`. Plugins that want their own error handling chain through the host's hook (§7.5).

The host owns:

- Frame stability signals from the framework
- Semantics tree capture
- The default action set: `tap`, `long_press`, `enter_text`, `scroll`, `scroll_until_visible`, `system_back`, `wait`, `inspect_widget`, `done`
- Screenshots
- The plugin contract enforcement (namespacing, budgets, lifecycle ordering)

The host does not own:

- Anything about specific routing libraries
- Anything about specific state management libraries
- Anything about specific networking clients
- Anything about specific analytics, telemetry, or logging libraries
- Anything about specific custom design systems beyond the configuration knobs Marionette also exposes (which can themselves be a plugin in this design)

### 6.2 The harness library (`exploration_agent`)

A Dart library that contains the perception-action loop. Connects to the running app via VM service URI; calls the binding's extensions to capture observations and execute actions; calls the model provider to decide on next actions; persists trajectories.

The harness is a *library*, not an executable. Two frontends in v1 consume it:

**CLI frontend (`exploration_cli`).** A Dart command-line tool. Scriptable, headless, the right interface for CI runs and batch trajectory collection. Takes a goal as argument or stdin, streams progress to stdout, writes the trajectory to disk.

**DevTools extension panel (`exploration_devtools`).** An in-IDE panel built on `package:devtools_extensions`. Provides interactive prompt entry, live thinking-trace streaming, and an interactive session timeline. Same harness, same binding, same VM service connection — just rendered as UI rather than CLI output.

Splitting the harness from its frontend means we don't reimplement the loop. Both frontends are thin shells around the same `ExplorationSession` API.

### 6.3 The DevTools extension (`exploration_devtools`)

A Flutter web app embedded as a tab in DevTools. Uses `package:devtools_extensions` for the extension framework, which gives us VM service connection, theming, and IDE integration for free. The extension auto-discovers when the user's app depends on `exploration_flutter`, and shows up as an "Exploration" tab in DevTools regardless of whether the user opens DevTools standalone, from VS Code, or from Android Studio.

Three panels in v1, each focused:

**Prompt panel.** A text field for the goal, a "Start" button, and configuration controls (model selection, session budgets, plugin enablement). Replaces the CLI's argument parsing for interactive use. The developer types what they want the agent to do and hits Start.

**Thinking panel.** Streams the model's reasoning trace into a scrollable pane as it generates. For the Qwen3.6 target, this is the `<think>...</think>` content the model emits before producing its action. Watching this in real time gives the developer fast intuition for whether the agent's mental model of their app is coherent — much faster than waiting for the trajectory file and reading it after the fact. The panel also surfaces the action the model ultimately selected and the validation result.

**Timeline panel.** A scrollable list of turns. Each row shows the action taken, a one-line summary of the diff, and the running summary at that point. Click a turn to expand it into a detail view: the full observation snapshot (semantics tree, route stack, plugin fragments, screenshot if enabled), the model's reasoning, the action and validation result. The timeline updates live as the session progresses and is also browsable after the session ends.

The panel deliberately does not duplicate everything the CLI does. It does not yet expose: long-form trajectory analytics, batch session runs, headless replay (v2 anyway), or plugin authoring tools. Those remain CLI-only or out of v1 entirely.

The panel runs the harness loop *inside the extension web app itself*, not as a separate process. This is feasible because DevTools extensions are full Flutter web apps with Dart capability and an established VM service connection. Running the harness in-panel means there's no extra IPC layer between the UI and the loop — the panel renders the same in-memory `ExplorationSession` state that drives the CLI.

### 6.4 Why a plugin architecture

Three reasons, in order of how much they shape the design:

**Routing diversity is unsolvable in the core.** Flutter has at least four major routing approaches in production use (imperative `Navigator`, declarative `Router` with `RouterDelegate`/`RouteInformationParser`, `go_router`, `auto_route`, `beamer`) plus custom `RouterConfig` setups, and a unified abstraction over them is lossy. The right answer is to let each routing approach contribute its own observation fragment in its own native shape. Routing is a plugin concern.

**The same generalizes.** State management (Riverpod vs BLoC vs Provider vs Redux), networking (Dio vs http vs Chopper), error reporting (Sentry vs Firebase Crashlytics vs Bugsnag), telemetry (PostHog vs Amplitude vs Segment) — every one of these is a place where the agent benefits from native visibility but where a unified abstraction is worse than letting each library expose itself.

**It distributes ecosystem work.** We can't ship and maintain support for every library. With a plugin contract, package maintainers can ship integration plugins. We ship the host, the contract, and reference plugins that target Flutter's built-in primitives.

### 6.5 Why not `integration_test`

`integration_test` is a test framework, not a runtime introspection framework. It runs the app under `IntegrationTestWidgetsFlutterBinding`, which uses fake-async, controlled time, and a `WidgetController` API designed for assertions. It conflicts with our binding (only one binding per app), it changes how network behaves, and it requires launching the app via `flutter test` rather than `flutter run`.

`integration_test` is the right substrate for **trajectory replay** (§15.4) where deterministic time and stubbed network are features, not bugs. That's a v2 feature.

`ExplorationBinding.run(...)` defuses the order-of-operations failure where a user constructs `GoRouter` (which calls `WidgetsFlutterBinding.ensureInitialized()` internally) before `ExplorationBinding.ensureInitialized(...)`. With `run`, the binding slot is claimed first; subsequent `WidgetsFlutterBinding.ensureInitialized()` calls become idempotent no-ops. The §6.5 install gate (rejecting `IntegrationTestWidgetsFlutterBinding` and other custom subclasses) remains active and unchanged.

## 7. The plugin contract

This is the load-bearing part of the v0.3 design. The contract is intentionally small.

### 7.1 The plugin interface

```dart
abstract class ExplorationPlugin {
  /// Stable namespace. Used for tool prefixing and observation fragment keys.
  /// Must match `^[a-z][a-z0-9_]*$`. Must be unique within a session.
  String get namespace;

  /// Tools this plugin contributes.
  List<ExplorationTool> get tools;

  /// Called once at host initialization, before any observation or action.
  /// Plugins register VM service extensions, install hooks, etc., here.
  Future<void> initialize(PluginContext context);

  /// Called by the host before each observation capture.
  /// Returns a structured fragment merged into the observation under
  /// `observation.plugins[namespace]`. Returns null to contribute nothing.
  Future<Map<String, Object?>?> observe(ObservationContext context);

  /// Called by the stability policy to ask whether the plugin considers
  /// the app busy. Used to delay observation capture until plugin-known
  /// async work completes.
  Future<BusyState> busyState();

  /// Called after each action is executed. Plugins use this to record
  /// the action in their own way (analytics, structured logs, etc.).
  Future<void> onActionExecuted(ExecutedAction action);

  /// Called when the session ends, in any state.
  Future<void> dispose();
}
```

### 7.2 Tools

A plugin's tools are typed Dart functions exposed to the agent:

```dart
class ExplorationTool {
  String get name;              // Namespaced: "go_router.navigate_to"
  String get description;       // For the model's tool selection
  JsonSchema get inputSchema;
  Future<ToolResult> call(Map<String, Object?> args);
}
```

Tool names are mandatorily namespaced — the host enforces `<plugin_namespace>.<tool_name>` at registration. Collisions are rejected at startup.

The host merges tools from all plugins with its own core tools (`tap`, `enter_text`, etc., which live in the reserved `core` namespace) into a single tool list presented to the model.

### 7.3 Observation fragments

Plugins return structured Dart maps from `observe()`. The host merges these into the observation:

```
observation = {
  core: {
    semantics: [...],
    routes: [...],          // Best-effort Navigator 1.0 view; declarative routers contribute their own fragments
    errors: [...],
    stability: {...},
  },
  plugins: {
    router: { current_route_name: "/checkout/payment", stack: ["/", "/checkout", "/checkout/payment"], arguments: {...} },
    riverpod: { invalidatable_providers: [...], recent_state_changes: [...] },
    dio: { in_flight: [...], recent_completed: [...] },
  }
}
```

The host enforces a per-plugin observation budget (default 1KB serialized, configurable). Plugins that exceed the budget have their fragment truncated with a warning. Plugins should return `null` when they have nothing relevant to contribute (for example, a routing plugin should return null when not on a route it manages).

### 7.4 Stability contributions

Plugins return a `BusyState` from `busyState()`:

```dart
class BusyState {
  final bool isBusy;
  final String? reason;        // Human-readable, included in stability metadata
  final Duration? estimatedDuration; // Best-effort, may be null
}
```

The host's stability policies (§9) treat any `isBusy: true` from any plugin as a reason to keep waiting, up to the policy's wall-clock budget. If the budget expires with plugins still busy, the observation is captured anyway and tagged with the busy plugins and their reasons.

This is the mechanism that solves the "wait for in-flight network requests" problem, the "wait for animations to settle" problem (which the host can also report on directly via `SchedulerBinding`), and "wait for our async store to commit" for state libraries.

### 7.5 Lifecycle hooks (additional to the core methods)

Plugins that need framework-level hooks can request them through `PluginContext` rather than subclassing the binding:

```dart
class PluginContext {
  /// Register a chained error handler. The host calls all registered handlers
  /// in registration order; each returns whether the error was handled.
  void registerErrorHandler(ErrorHandler handler);

  /// Register a callback for VM service extension methods.
  void registerExtension(String suffix, ExtensionHandler handler);
  // The host registers this as `ext.flutter.${plugin.namespace}.${suffix}`.

  /// Subscribe to per-frame callbacks if the plugin needs them.
  /// Use sparingly; this runs on every frame.
  void registerFrameCallback(FrameCallback callback);
}
```

This is the mechanism that lets plugins do framework-level things without subclassing the binding (which would conflict with the host's binding ownership).

### 7.6 Plugin registration

Plugins are registered at host initialization:

```dart
void main() {
  if (kDebugMode) {
    ExplorationBinding.ensureInitialized(
      plugins: [
        RouterExplorationPlugin(navigatorKey: rootNavigatorKey),
        RiverpodExplorationPlugin(container: providerContainer),
        DioExplorationPlugin(dio: appDio),
      ],
    );
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  runApp(MyApp());
}
```

Plugins are user-instantiated, which is the only realistic option in Dart's compilation model. We don't try to auto-discover plugins from `pubspec.yaml` in v1; we expect users to wire them up explicitly. The CLI can scaffold this for common configurations.

**Discovery convention.** Plugin packages should declare their presence via `extension/exploration/config.yaml`, following the same pattern as Jake MacDonald's "Packaged AI Assets" proposal for the Dart MCP server. This is purely conventional in v1 — the host doesn't read it — but adopting the convention now means that if we later add auto-discovery, well-behaved plugin packages are already discoverable. The config declares the plugin's namespace, the Dart class to instantiate, and any constructor requirements the user must satisfy. A v2 auto-discovery mechanism could read these manifests, generate a plugin-instantiation file, and reduce the explicit-registration burden in `main()`.

This alignment matters for ecosystem coherence. A package that wants to support both coding-time agents (via the Dart MCP server) and runtime exploration (via this project) can ship both `extension/mcp/config.yaml` and `extension/exploration/config.yaml` from the same package, and consumers see the package's full agent integration story in one place.

### 7.7 Versioning posture

Plugin updates that add tools, expand observation fragments, or refine busy-state heuristics are **not breaking changes**. Plugin authors should release as often as they want. The host treats unfamiliar fields in observation fragments as opaque and passes them through; new tools simply appear in the merged tool list. Breaking changes are reserved for changes to the plugin contract itself (the `ExplorationPlugin` interface), which the host versions explicitly.

This posture mirrors the Packaged AI Assets design's stance on resource updates and reflects the same underlying principle: AI integration improvements should not be gated on semver overhead.

### 7.8 Plugin ordering and isolation

Plugins run in registration order for `observe()`, `busyState()`, `onActionExecuted()`, and `dispose()`. The host catches and logs exceptions from any plugin method without aborting the session — a misbehaving plugin degrades to "no contribution this turn" rather than killing the whole loop.

A plugin's failure does not affect another plugin's contribution. Each `observe()` call runs in its own try/catch. A plugin that throws three times in a row is automatically disabled for the rest of the session, with a clear log entry.

## 8. Resources and prompts (deferred to v2)

The plugin contract above covers tools (agent-invoked), observations (host-merged context), and lifecycle hooks. Two adjacent capabilities exist in the MCP world that we deliberately defer:

**Resources.** Static or dynamic content a plugin makes available to the agent on demand or by reference (e.g., `@routes` to inject a list of all registered routes into the prompt). These are passive — the agent reads them; they don't drive action.

**Prompts.** Pre-authored multi-step workflows the user invokes (typically as slash commands in chat-style UIs), which the model then executes. These bridge the gap between "user types a single instruction" and "user composes a complex prompt from scratch."

Both are first-class in the MCP specification and are the entire surface of Jake MacDonald's "Packaged AI Assets" proposal for the Dart MCP server. For coding-time agents in IDEs, these are the right primitives — `@slivers` injects the slivers tutorial, `/split_into_subwidgets` runs a refactor workflow.

For our exploration agent in v1, neither is necessary. Our agent's interaction model is goal + autonomous loop, not chat-with-resource-injection. We add them when:
- A user-facing chat interface for the exploration agent is on the roadmap (v2 at earliest).
- A plugin author needs to inject app-specific reference material into the agent's context that doesn't fit cleanly into the per-turn observation budget. (Today they can just put it in their observation fragment; the budget enforcement is the only real reason to want a separate resource channel.)

**The plugin contract should leave room for these.** Specifically, the `extension/exploration/config.yaml` manifest should use a structure compatible with adding `resources:` and `prompts:` keys later, and the plugin Dart interface should be able to add `List<ExplorationResource>` and `List<ExplorationPrompt>` getters in a backward-compatible way. Plugins that author resources/prompts for a coding-time agent today (via Packaged AI Assets) should be able to share the same source files when our resource/prompt support arrives.

This isn't speculative complexity — it's a documented v2 path that prevents painting ourselves into a corner.

## 9. The stability primitive

This replaces `pumpAndSettle` for the same reasons as v0.2 (real apps never settle in the test-framework sense) and adds plugin-contributed busy-state.

### 9.1 Stability policies

Three default policies, each composing framework signals with plugin contributions:

**Action-relative (default).** Wait until any of: route stack changes, semantics tree changes, *no plugin reports busy*, or 800ms wall-clock. Whichever first. Best matches "did my action do something visible?" and terminates promptly.

**Quiet-frame.** Wait until N consecutive frames have committed with no transient callbacks, no pending microtasks, *and no plugin reports busy* (default N=2). Terminates only when the app is genuinely idle. Useful for first observation of a session.

**Bounded-stability.** Wait until quiet-frame is achieved or 1500ms wall-clock. On budget expiration, capture anyway and tag the observation with what's still busy. Honest middle ground.

The model can request a specific policy for its next observation via a `wait_strategy` field on its action.

### 9.2 What gets reported

The stability metadata included in the observation:

```
stability: {
  policy: "action_relative",
  terminated_by: "semantics_changed" | "route_changed" | "all_idle" | "budget_expired",
  duration_ms: 240,
  framework_busy: { transient_callbacks: 0, microtasks: 0 },
  plugins_busy: [
    { namespace: "dio", reason: "2 in-flight requests", est_ms: 350 }
  ]
}
```

This goes into the prompt verbatim. The model knows whether it's looking at a stable observation or one captured under duress, and can adjust.

## 10. The perception-action loop

Each turn:

1. **Stabilize.** Host calls `getStableObservation(policy)`, which polls framework signals and `busyState()` from all plugins until the policy terminates.
2. **Capture core fragment.** Semantics tree, route stack (best-effort Navigator 1.0), errors, stability metadata.
3. **Capture plugin fragments.** Host calls `observe()` on each plugin, applies budget, merges results.
4. **Diff.** Compute structural diff against the previous observation, including plugin fragments.
5. **Build prompt.** Assemble: AGENTS.md + goal + running summary + last N actions verbatim + observation + diff.
6. **Decide.** Call the model with constrained output.
7. **Validate.** Check the proposed action exists in the merged tool list and its arguments match the schema. For host tools that target semantic node IDs, also validate the node exists.
8. **Act.** Execute via the appropriate VM service extension (host or plugin).
9. **Notify.** Call `onActionExecuted()` on every plugin.
10. **Persist.** Append to trajectory log.

Turn budget: 30s wall-clock. Session budget: 50 turns or 15 minutes wall-clock.

## 11. Observation representation

### 11.1 Core fragment

The host's contribution: semantics tree (primary), route stack (best-effort), errors, stability metadata. Optionally a screenshot. The semantics tree is the agent's primary action surface; everything else provides context.

**Screenshot default depends on the model.** When the configured model is vision-capable (the Qwen3.6-35B-A3B target case, frontier models with vision), screenshots default **on** and are included with each observation. The model uses them to disambiguate semantically-similar nodes, fall back when the semantics tree is sparse, and cross-reference visual changes against semantic ones. When the model is text-only, screenshots default off. The host detects model capabilities through the provider abstraction; users can override.

### 11.2 Plugin fragments

Per-plugin structured data merged under `observation.plugins.<namespace>`. Each plugin owns its key.

### 11.3 Diff

The diff covers both core and plugin fragments. Each plugin's diff is computed independently (the harness keeps the previous fragment and computes a structural delta). Plugins that don't define a delta-friendly shape get a "previous vs current" pair instead of a structured diff; this is the fallback for plugins with opaque blobs.

### 11.4 Budget management

Default total observation budget: 6KB serialized (~2K tokens). Distributed as:
- Core: 4KB
- Plugins: 2KB total, distributed by configured per-plugin budgets

The host warns when fragments are truncated. For local models on hardware with generous KV cache (the M3 Ultra target), these defaults can be raised; the host accepts overrides via session config.

## 12. Action space

Every action is a tool call. Tools come from two places:

### 12.1 Core tools (host-provided, `core` namespace)

`core.tap`, `core.long_press`, `core.enter_text`, `core.scroll`, `core.scroll_until_visible`, `core.gesture`, `core.system_back`, `core.wait`, `core.inspect_widget`, `core.done`. Targets are semantics node IDs.

### 12.2 Plugin tools

Anything plugins contribute. Examples from reference plugins:

- `router.navigate(route_name, arguments?)` — programmatic navigation that bypasses UI hit-testing when the agent already knows where it wants to go.
- `riverpod.invalidate_provider(provider_id)` — force-refresh state for testing.
- `dio.cancel_in_flight()` — cancel pending requests, useful for adversarial testing.

The model picks tools by name from the merged list. The harness validates against the schema regardless of source.

### 12.3 Action targeting

Core tools target semantics node IDs (stable per session). Plugin tools target whatever the plugin defines — provider IDs, route paths, request IDs. The plugin owns identifier stability for its own targets.

## 13. Memory: summary vs. diff

Unchanged from v0.2:

- **Running summary.** Model-authored, session-spanning, ~500 token soft budget, ~1000 hard cap.
- **Per-turn diff.** Host-authored, single-turn, ~200-500 tokens typical. Now includes plugin diffs.
- **Last N actions.** Last 3-5 verbatim, including outcomes.

## 14. Trajectory persistence

JSONL per session. Each record includes which plugins contributed and their fragment versions, so trajectories remain readable even if a plugin is later removed or upgraded.

## 15. Use cases

Unchanged from v0.2:

- §15.1 Open-ended exploration (v1)
- §15.2 Goal-directed exploration (v1)
- §15.3 Adversarial exploration (v2)
- §15.4 Trajectory replay under `integration_test` (v2)
- §15.5 Trajectory collection for fine-tuning (out of scope)

## 16. Model integration

### 16.1 Provider abstraction

`ModelProvider` interface. v1 implementations: local MLX (OpenAI-compatible HTTP), Anthropic, OpenAI. Existing Dart packages (`dartantic_ai`, per-provider SDKs) for plumbing.

### 16.2 Constrained output

JSON-schema-constrained for `{action: {tool, args}, summary_update, rationale?, wait_strategy?}`. Schema is dynamically composed each turn from the current merged tool list (different plugins → different available tools → different valid action shape).

### 16.3 Primary target: Qwen3.6-35B-A3B at 8-bit on M3 Ultra

The harness is designed primarily around running against an MLX-served Qwen3.6-35B-A3B at 8-bit quantization, on a 96GB M3 Ultra. Key facts about this model that shape the design:

**Vision-language model, not text-only.** Qwen3.6-35B-A3B is image-text-to-text. Screenshots are a first-class input modality, not an optional fallback. We default screenshots **on** for the exploration agent. The semantics tree remains the primary action surface, but screenshots give the model fallback context for screens with sparse semantics (heavily custom-painted UI, charts, image-heavy content) and for visual disambiguation when the agent is unsure which of several similar-looking nodes to act on.

**MoE with strong agentic posture.** 35B total parameters, ~3B active per forward pass. Reported benchmarks show SWE-bench Verified 73.4, Terminal-Bench 2.0 51.5, MCPMark 37.0. The model is trained for tool-use as a first-class workload. The merged tool list of ~14 tools (host + 3 reference plugins) is well within the size class this model handles competently; tool-selection accuracy is unlikely to be the bottleneck.

**Tool-call parser is `qwen3_coder`.** Both vLLM and SGLang require `--tool-call-parser qwen3_coder` for proper tool use. **MLX support requires verification before build commits.** `mlx-vlm` may or may not handle the same parser format; if it doesn't, the local-inference story shifts to either using `mlx-lm` with the text-only mode (losing vision) or moving to SGLang on Linux (losing the M3 Ultra). This is a pre-build spike: stand up the inference server, run a tool-calling smoke test, confirm structured output works.

**Native context is 262,144 tokens.** Massive. Earlier concerns about plugin observation budget pressure are essentially moot at this context length. We can carry rich observation history in-context; the limit is more about model attention quality at long context than about hitting the limit.

**Thinking-mode preservation via `preserve_thinking: true`.** Qwen3.6 supports retaining reasoning traces from historical messages, which Qwen explicitly recommends for agent scenarios. This changes our prompt construction: instead of rebuilding context from scratch each turn, we carry the model's previous reasoning forward. Benefits include better decision consistency, improved KV cache reuse, and reduced redundant reasoning. The harness should enable `preserve_thinking` by default for the local-inference path.

**Sampling defaults.** Qwen recommends, for thinking mode on general tasks: `temperature=1.0, top_p=0.95, top_k=20, presence_penalty=1.5, repetition_penalty=1.0`. The high `presence_penalty` (1.5 vs typical 0) is the unusual one — Qwen specifically calls it out as helping reduce repetitive outputs for agent scenarios, where "the agent keeps trying the same action" would manifest. Adopt these defaults; document that they're tuned for Qwen3.6 specifically and will need adjustment for other models.

### 16.4 Other model tiers

Frontier (Claude Sonnet 4.6+, GPT-5-class via API) as fallback for tasks where the local model stalls. 14B–32B dense alternatives (Qwen2.5-Coder-32B and similar) for hardware without M3 Ultra-class memory. Below 7B not recommended for open-ended exploration. Each tier ships with its own sensible defaults (lower temperature for smaller models, tighter retry budgets, smaller observation defaults).

## 17. Failure modes

- **Stability budget expired with plugins still busy.** Capture anyway, tag observation with busy plugins. Not a failure.
- **Invalid action.** Up to 3 retries against the same observation. Failure = failed turn.
- **Malformed model output.** One retry with schema error. Second failure = failed turn.
- **3 consecutive failed turns.** End session, `harness_error: agent_stuck`.
- **Plugin throws during `observe()`, `busyState()`, or `onActionExecuted()`.** Logged, that turn proceeds without the plugin's contribution. 3 consecutive failures auto-disable the plugin.
- **Plugin throws during `initialize()`.** Plugin marked failed at startup; session continues without it. Logged loudly.
- **Runtime error in app under test.** Captured in observation, doesn't end session.
- **VM service connection lost.** End with `harness_error: connection_lost`. Trajectory preserved.
- **Binding not initialized.** Detected on connect; clear error pointing at setup.

## 18. v1 scope

### Ships in v1

**Core:**
- `exploration_flutter` — the host binding package. `ExplorationBinding`, plugin contract, core tools, stability policies, VM service extensions.
- `exploration_agent` — the harness library. Perception-action loop, model providers (local MLX, Anthropic, OpenAI), trajectory persistence. Consumed by both v1 frontends.

**Frontends:**
- `exploration_cli` — command-line tool. Goal as argument or stdin, streams progress, writes trajectory to disk. Right interface for CI runs and batch trajectory collection.
- `exploration_devtools` — DevTools extension panel. Three sub-panels: prompt entry with model/budget configuration, live thinking-trace stream, interactive session timeline. Auto-discovered by DevTools when the user's app depends on `exploration_flutter`. Works in standalone DevTools, VS Code, and Android Studio.

**Reference plugins:**
- `exploration_router` — routing observation + `navigate` tool. Targets Flutter's built-in `Router` and `Navigator` primitives directly. No third-party routing dependency. Validates the routing-diversity solution by demonstrating the contract can express the most general case; framework-specific plugins (`go_router`, `auto_route`, `beamer`) become straightforward to author by following this pattern.
- `exploration_riverpod` — state observation + `invalidate_provider` tool. Validates structured state contribution.
- `exploration_dio` — networking observation + busy-state hook + `cancel_in_flight` tool. Validates the busy-state mechanism.

**Documentation:**
- AGENTS.md template
- Plugin authoring guide (see §19)

Three plugins is the minimum to prove the contract works across the three plugin shapes (observation, lifecycle hook, action contribution). Choosing raw `Router`/`Navigator` over `go_router` for the routing reference is deliberate: it stresses the contract more honestly (no clean RouterDelegate API to lean on, just whatever the user has wired up), avoids picking a winner among third-party routers, and produces a plugin that works against any app without imposing a routing-framework choice on the host.

### Not in v1

- A Marionette compatibility plugin. Nice-to-have but not required for the design to validate; revisit once the contract is stable.
- Adversarial exploration.
- Trajectory replay under `integration_test`.
- Multi-device parallel sessions.
- DevTools panel features beyond the three v1 sub-panels — long-form trajectory analytics, batch session management UI, plugin authoring tooling, replay UI.
- Trajectory-based fine-tuning.
- Custom gestures beyond the discrete kinds in §12.1.
- Demonstration recording.
- Hot-reload-aware sessions.
- Auto-discovery of plugins from `pubspec.yaml`.

## 19. Plugin authoring guidance (v1 documentation deliverable)

Not a section of the host, but a deliverable: a guide for writing a plugin. Includes:

- The contract (§7) with worked examples.
- The reference plugins as readable source.
- Conventions: namespace selection, observation budget management, when to report busy.
- Anti-patterns: subclassing the binding, hogging frame callbacks, returning unbounded observation fragments, swallowing exceptions.
- A template package generator (`exploration_plugin create my_plugin`).

See: [Plugin Authoring Guide](./plugin_authoring_guide.md).

## 20. Wrapping existing tools as plugins

The plugin contract is general enough to wrap existing tools, with one caveat: any existing tool that owns its own `WidgetsBinding` can't be wrapped via composition.

### 20.1 Marionette as a plugin (post-v1, contingent)

Marionette is the most relevant existing tool. It's reasonable to want a `MarionetteCompatibilityPlugin` that exposes Marionette's familiar tool set (`get_interactive_elements`, `tap`, `enter_text`, `scroll_to`, `take_screenshots`, `get_logs`, `hot_reload`) through the host.

Three approaches, in viability order:

**Inheritance (preferred).** `ExplorationBinding extends MarionetteBinding`. Inherits all `ext.flutter.marionette.*` extensions; the plugin is a Dart-side shim that exposes them through the contract. Contingent on `MarionetteBinding` being open to extension (Apache 2.0 license is permissive but the class itself may be hostile to subclassing). Verify in source before committing.

**Reimplementation.** Reimplement Marionette's primitives in our own binding. Marionette's surface is small enough that this is bounded work. Loses free updates but avoids inheritance fragility. The reimplemented plugin would be `exploration_marionette_compat`, intentionally API-shaped after Marionette without sharing code.

**Coexistence.** Not viable. Two bindings cannot coexist in a single Flutter app.

The right move is to ship v1 without Marionette compatibility, validate the contract with the three reference plugins, then attempt the inheritance approach in v1.1 once the contract is stable. If inheritance proves brittle, fall back to reimplementation.

### 20.2 Generalizing the lesson

Any existing package that owns its own framework-level hooks (binding, error handler, scheduler integration) faces the same constraint. Plugins for these tools fall into one of:

- **Configuration plugins:** the existing tool exposes a config knob; the plugin sets it.
- **Composition plugins:** the existing tool is a normal package without binding ownership; the plugin instantiates it and exposes its API.
- **Subclass plugins:** the existing tool owns a binding; the plugin requires our binding to subclass theirs.
- **Reimplementation plugins:** the existing tool is closed to subclassing; the plugin reimplements relevant behavior.

This taxonomy belongs in the plugin authoring guide.

## 21. Open questions

- The 800ms default for action-relative stability still needs empirical tuning against real apps.
- Tool-selection accuracy with the dynamic merged tool list on Qwen3.6-35B-A3B is *probably* fine given the model's reported agentic-coding benchmarks (SWE-bench Verified 73.4, MCPMark 37.0, MCP-Atlas 62.8), but should be validated empirically once the harness is running. The pre-build verification of `mlx-vlm` tool-call parser support (§16.3) is the more pressing dependency.
- Should plugins be able to declare hard dependencies on other plugins (`exploration_dio` requires `exploration_logging`)? Default position: no. Plugins should be independent. Revisit if it becomes a real friction.
- For plugin-contributed tools that target plugin-owned identifiers (`provider_id`, `request_id`), how does the agent learn what valid IDs look like? Default: each plugin's observation fragment includes the IDs it'll accept as inputs to its tools. Document this convention.
- Should the DevTools panel allow the user to *interrupt* the agent mid-turn — e.g., to cancel a long generation, or to inject a hint into the running summary? Default position: yes, both, but only if it's cheap to implement on top of the existing session state. If it adds meaningful complexity, defer to v2. The user will benefit from being able to stop a session that's clearly going off the rails without having to wait for the budget to expire.

## 22. Risks

- **Plugin contract churn.** If we change the contract after the ecosystem starts publishing plugins, we break them. Mitigation: keep v1 contract minimal, mark it explicitly experimental, and version it. Don't promise stability until v2.
- **Reference plugins not representative.** If raw `Router`/`Navigator`, Riverpod, and Dio cover 80% of cases, great. If not, the contract may need additions. Mitigation: actually try the reference plugins against real apps before declaring the contract done.
- **Plugin observation budget pressure.** Three plugins at 1KB each plus core at 4KB is 7KB; this fits comfortably in the 262K-token Qwen3.6 context but tighter hardware would feel it. Mitigation: configurable budgets, plus document expected token costs prominently.
- **Plugin authors disagree about identifiers.** `Router` plugins use route names or paths; Riverpod uses provider IDs; Dio uses request IDs. The model has to keep these distinct. Mitigation: enforce namespacing rigorously, document the convention, see whether the model actually struggles with this in practice (it might not given Qwen3.6's tool-use training).
- **mlx-vlm tool-call parser may not match `qwen3_coder` semantics.** The local-inference path depends on this. Mitigation: pre-build verification spike (§16.3). If `mlx-vlm` doesn't support the parser cleanly, fallback options are `mlx-lm` text-only mode (loses vision, which we now rely on for screenshot input) or moving local inference to SGLang on Linux (loses the M3 Ultra setup).
- **Local model ceiling.** Qwen3.6-35B-A3B may not handle long-horizon goal-directed exploration on complex apps. Mitigation: ship with frontier model fallback.
- **VM service surface stability.** Pin minimum Flutter version, track via dart-lang/ai.
- **Marionette inheritance brittleness.** If we commit to wrapping Marionette via subclassing and they restructure their binding, we break. Mitigation: don't ship Marionette compat in v1; validate the approach first.
- **Harness-in-web-app constraints.** Running the harness loop inside the DevTools extension's Flutter web app means the harness can't depend on dart:io or other non-web Dart libraries. Mitigation: keep the harness web-compatible by construction; isolate any io-requiring code to the CLI frontend. Trajectory persistence in the DevTools panel goes through the Dart Tooling Daemon's filesystem APIs, not direct disk access.
- **Model provider feasibility from web.** Local MLX inference is HTTP, fine from web. Anthropic and OpenAI are HTTP, fine. But CORS configuration may be required for browser-based requests to local inference servers. Mitigation: document the required CORS headers for `mlx-vlm` (and the SGLang/vLLM fallback paths); ship a sample server config.
- **DevTools extension version skew.** The `devtools_extensions` API is still evolving. Mitigation: pin a minimum DevTools version, watch the package's CHANGELOG, accept that v1 may need a minor follow-up release if breaking changes land.

## 23. Success criteria

- A user can install the host, configure 1-3 plugins, and run an exploration session on a representative app in under 15 minutes from the install command.
- Qwen3.6-35B-A3B at 8-bit can complete the "log in via `Navigator`-managed routes, find a settings screen, change a Riverpod-managed setting, log out" task on a representative app in <20 turns, ≥80% of attempts.
- The action-relative stability policy terminates within budget on ≥95% of post-action turns, including correctly waiting for `dio` in-flight requests.
- A third party can write a working plugin (any of the four taxonomies in §20.2) by reading only the plugin authoring guide, with no need to read host source.
- The reference plugins individually compose with each other and with apps that use only some of `Router`/`Navigator`, Riverpod, and Dio. None of the reference plugins is required to run a session.
- A 30-minute exploration session produces a trajectory file under 50MB, reviewable both in the CLI viewer and in the DevTools timeline panel without performance degradation.
- The DevTools panel auto-discovers when the user's app depends on `exploration_flutter` and presents a usable prompt-and-watch loop within 30 seconds of the developer opening DevTools — no manual configuration, no separate process to launch.
- The thinking-trace stream in the DevTools panel keeps up with the model's generation rate (no perceptible lag between token production and display) on the M3 Ultra target hardware.
