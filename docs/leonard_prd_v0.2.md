# Leonard — PRD (superseded by v0.5)

**Status:** Draft v0.2
**Author:** Nico
**Last updated:** 2026-05-07

**Changes from v0.1:** Corrected the runtime architecture. v0.1 conflated `integration_test` (a test framework) with the runtime introspection an exploration agent needs. v0.2 uses a custom `WidgetsBinding` in the running app (Marionette-style) and replaces `pumpAndSettle` with an explicit stability-policy primitive. `integration_test` moves from v1's exploration substrate to a v2 replay substrate. Model tier guidance updated for Qwen3 35B-A3B at 8-bit on M3 Ultra (96GB).

---

## 1. Summary

A Dart-based agent harness that drives a running Flutter application via a custom `WidgetsBinding` exposing VM service extensions, centering each agent turn on a stable observation of the app. The agent is goal-conditioned and open-ended — it can be asked to explore, to reach a specific state, or to characterize an app it has never seen.

The harness operates against the *real running app*, not a test entrypoint. Real network, real time, real animations. Stability is defined by the harness using observable frame-lifecycle signals, not by `pumpAndSettle`. The harness is **not** a test generator and **not** a code-writing agent. It is a perception-action loop: capture a stable observation of the app, decide on an action, execute it, observe the consequences. Useful applications follow from that primitive.

## 2. Motivation

Browser automation agents have a chronic problem: they don't know when their actions complete. Every observation is a snapshot of indeterminate freshness, and a large fraction of failures are races against animations, network calls, or partial renders.

Flutter is structurally different. The framework's `SchedulerBinding` exposes the frame lifecycle directly — pending frames, transient callbacks (animations), persistent callbacks (per-frame work), pointer event processing, and microtask state are all introspectable. Combined with the semantics tree, route stack, and runtime error stream, this gives an agent something rare: discrete, indexable time grounded in observable signals about what the app is actually doing.

The Dart Tooling Daemon and the official Dart MCP server wrap parts of this surface for IDE-side use. Marionette MCP wraps a different slice for runtime UI interaction. This project takes a related but distinct bet: drive the same primitives directly from Dart, with the agent loop, observation packing, action validation, and stability policy all living in one process the user controls. This produces a tighter, more debuggable, more type-safe loop — at the cost of being a separate codebase from the official MCP path.

## 3. Goals & non-goals

### Goals

- Provide a perception-action loop where one turn corresponds to one stable observation of the running app, with stability defined by the harness, not by `pumpAndSettle`.
- Produce an observation representation compact enough for local models (≤8K tokens for typical apps) without losing actionable information.
- Make trajectories deterministic enough for human review and structural replay; full execution-level replay is a v2 concern.
- Validate proposed actions against the live semantics tree before execution to keep local-model errors from costing full turns.
- Maintain two distinct forms of session memory: a *running summary* authored by the model, and a *per-turn diff* authored by the harness.
- Support pluggable model backends, with first-class support for a local MLX-served Qwen3 35B-A3B and frontier APIs as fallback.
- Run on every platform the target Flutter app runs on, including web and desktop.

### Non-goals

- Generating new Flutter code, including new tests. The agent only acts on the running app.
- Replacing the Dart MCP server, Marionette MCP, or other MCP-shaped tools. Those are for IDE-side workflows; this is for harness work where the user controls the loop end to end.
- Self-improving training loops, RL, or fine-tuning pipelines. Trajectory collection is in scope; what's done with the trajectories is downstream.
- General-purpose mobile UI testing across React Native, native iOS, native Android. Flutter only.
- Running against a release-mode app. The harness depends on debug-mode VM service extensions and is debug/profile only.

## 4. Target users

- **Flutter developers** running exploration sessions against their own apps to find broken flows, dead routes, or accessibility gaps.
- **QA and reliability engineers** running long-form exploration sweeps and capturing trajectories for review.
- **Researchers and tinkerers** collecting (observation, action) trajectories for downstream work — fine-tuning small models on app-specific behavior, building benchmark suites, or evaluating frontier models on grounded tasks.

The first audience shapes the API. The other two are why the trajectory format is first-class.

## 5. Concepts and terminology

**Turn.** One iteration of the perception-action loop. Begins with a stability wait, ends with action execution.

**Stability policy.** The harness's rule for deciding when an observation is worth capturing. Replaces `pumpAndSettle`'s test-framework semantics. See §7.

**Observation.** The harness's snapshot of the app at a turn boundary. Contains the semantics tree, route stack, recent runtime errors, frame stability metadata, and optionally a screenshot.

**Action.** A typed call to a binding-provided actuator — tap, enter text, scroll, gesture — targeted at a semantics node identifier.

**Diff.** Mechanical, harness-authored description of what changed between the previous observation and the current one. One per turn.

**Running summary.** Narrative, model-authored description of the agent's accumulated knowledge of the app. Updated each turn, but spans the session.

**Trajectory.** The full sequence of (observation, action, diff, summary) tuples for a session, plus the goal, AGENTS.md, and final summary.

**Goal.** The user-provided objective for the session. Free-text.

## 6. Architecture

The system is two pieces, communicating over the VM service:

### 6.1 The in-app binding (`leonard_flutter`)

A Dart package the user adds to their Flutter app. It provides `LeonardBinding extends WidgetsFlutterBinding`, which the user initializes in `main()` (debug/profile only, gated on `kDebugMode`). The binding:

- Replaces the default `WidgetsBinding`. **This means it conflicts with `IntegrationTestWidgetsFlutterBinding` and other custom bindings; only one is allowed per app instance.** This is a hard constraint of Flutter's architecture, not a design choice.
- Registers VM service extensions for: capturing the semantics tree, capturing the route stack, executing actions (tap, enter text, scroll, etc.), and querying frame-stability state.
- Hooks into `SchedulerBinding` callbacks to track transient callbacks (animations), persistent callbacks (per-frame work), pending microtasks, and frame commit/skip events.
- Maintains a bounded ring buffer of recent runtime errors via `FlutterError.onError` and `PlatformDispatcher.instance.onError`.
- Exposes a `getStableObservation(policy)` extension that the harness calls; the binding waits for the policy's stability condition (or its bounded timeout) before returning.

The binding is intentionally minimal — it is a *publisher* of observable state and an *executor* of actions, nothing else. All policy lives in the harness.

### 6.2 The harness (`leonard_agent`)

A Dart program (CLI for v1) that connects to the running app's VM service URI and orchestrates the agent loop. The harness:

- Owns the stability policy.
- Owns the prompt construction, model invocation, and action validation.
- Owns the trajectory log.
- Talks to the model via a pluggable provider abstraction.

Sessions run as a single Dart process talking to a single Flutter app instance.

### 6.3 Why not `integration_test`

`integration_test` is a test framework. It runs the app under `IntegrationTestWidgetsFlutterBinding`, which uses fake-async, controlled time, and a `WidgetController` API designed for assertion-driven test code. It is excellent at what it does — and what it does is *test*, not *explore*. Three concrete reasons it doesn't fit v1:

- It conflicts with any other custom binding. We can't have both the in-app binding above and the integration_test binding.
- The user has to launch the app via `flutter test` rather than `flutter run`. The agent doesn't show up in your normal dev session; it shows up in a special test entrypoint.
- Fake-async means network calls behave differently than they do at runtime. Stubbing network is a feature for tests; for an exploration agent you want to see how the app actually behaves.

`integration_test` is the right substrate for the **replay** use case (§11.4) — deterministic time, stubbed network, and reproducibility in CI are exactly what replay needs. That's a v2 feature.

## 7. The stability primitive

This replaces v0.1's `pumpAndSettle` approach.

### 7.1 The problem with `pumpAndSettle`

`pumpAndSettle` is a test primitive. It loops `pump` until no frames are scheduled or a timeout fires. In a real running app it almost never reaches the no-frames-scheduled state, because real apps have animations that loop, periodic timers, network polling, and other legitimate reasons to keep scheduling work. The timeout fires constantly. "Did the app settle?" is the wrong question.

### 7.2 The right question

The right question is **"did anything observable change in response to my action, and is the app currently stable enough that another observation would yield the same answer?"** This decomposes into observable signals:

- Did the route stack change since the action?
- Did the semantics tree change since the action?
- Are there currently any transient callbacks running (animations)?
- Are there any pending microtasks?
- How long has it been since the action?

### 7.3 Stability policies

The binding exposes the raw signals; the harness picks a policy. Three default policies:

**Action-relative (default).** Wait until either (a) the route stack changes, (b) the semantics tree changes in any node, or (c) a wall-clock budget expires (default 800ms). Whichever comes first. This best matches "did my action do something?" and terminates promptly even if the app has long-running animations.

**Quiet-frame.** Wait until N consecutive frames have committed with no transient callbacks and no pending microtasks (default N=2). Terminates only when the app is genuinely idle. Useful for the first observation of a session or after navigating to a new screen and wanting to let it fully settle.

**Bounded-stability.** Wait until quiet-frame is achieved *or* a wall-clock budget expires (default 1500ms). On budget expiration, capture anyway and tag the observation with what's still busy ("3 animations still running, 1 microtask pending"). The honest middle ground for screens that animate forever.

The harness defaults to action-relative for post-action observations and quiet-frame for the initial observation. The model can request a specific policy for its next observation via a `wait_strategy` field on its action — useful for cases like "I just tapped a button that opens a modal, give me time to let it animate in."

### 7.4 What the binding exposes

`getStableObservation` takes a policy and returns:

- The captured observation (semantics tree, route stack, errors).
- A `stability` block describing how the policy terminated: the reason (changes detected, quiet frame achieved, budget expired), the wall-clock duration, and what was still busy at capture time.

The harness uses the stability block as part of the observation it shows the model. The model knows whether it's looking at a snapshot of a fully-settled app or a snapshot of a still-busy app, and can decide accordingly.

## 8. The perception-action loop

Each turn proceeds:

1. **Stabilize.** Call `getStableObservation(policy)` on the binding. Returns when the policy's condition is met or its budget expires.
2. **Diff.** Compute structural diff against the previous turn's observation.
3. **Build prompt.** Assemble: AGENTS.md (static prior) + goal + running summary + last N actions verbatim + current observation + diff + stability metadata.
4. **Decide.** Call the model with constrained output (JSON schema for the action plus the summary update plus optional next-turn `wait_strategy`).
5. **Validate.** Check the proposed action against the current semantics tree. Does the target node ID exist? Is it enabled and visible? If not, return the validation failure to the model with up to 3 retries against the *same* observation.
6. **Act.** Execute the validated action via the binding's VM service extension.
7. **Persist.** Append the (observation, action, diff, summary) tuple to the trajectory log.

Turns have a hard wall-clock budget (default 30s) covering all six steps. Sessions have a hard turn-count budget (default 50) and a hard wall-clock budget (default 15 minutes). Either budget exhausting ends the session cleanly with a final summary.

## 9. Observation representation

### 9.1 Semantics tree (primary)

The agent's primary view of the app. Compact, action-oriented, matches the agent's decision space. Each node carries:

- A stable identifier assigned by the binding (a numeric ID, stable across observations within a session).
- The role (button, text field, header, image, etc.).
- The label (visible or accessibility label).
- The state flags (enabled, focused, selected, checked, on-screen).
- The available actions (tap, long-press, scroll, etc.).

Nodes that are off-screen, fully obscured, or marked `excludeSemantics` are omitted.

The binding allows configuration of additional widget types as "interactive" for apps with custom design systems, similar to Marionette's `MarionetteConfiguration.isInteractiveWidget`. This is essential for non-trivial apps where the standard semantics surface misses custom buttons and inputs.

### 9.2 Route stack

The current navigator stack, top to bottom. Critical for spatial grounding. Serialized as a list of route names plus exposed `RouteSettings.arguments`. For apps using `Navigator 2.0` declaratively, the harness falls back to a best-effort representation derived from the active `Router` configuration. (Validating this against a real Navigator 2.0 app before v1 ships is in §17.)

### 9.3 Runtime errors

Errors emitted since the previous turn — unhandled exceptions, framework asserts, render errors. Each error includes the message, the first 5 frames of the stack trace, and the wall-clock offset from the previous action. Older errors are dropped from a bounded ring buffer (default 50 entries).

### 9.4 Stability metadata

The block returned from `getStableObservation` (see §7.4). Included verbatim in the prompt.

### 9.5 Screenshot (optional)

Off by default. When enabled and the model is multimodal, included as a base64 PNG. For Qwen3 35B-A3B (text-only), default off.

### 9.6 Widget tree (on demand)

Not included in the default observation. Exposed as the `inspect_widget` action; the model can request it for a specific node. The cost of an extra turn is paid only when needed.

### 9.7 Diff

Computed by the harness, structured as four lists:

- **Route changes.** Pushed, popped, replaced.
- **Nodes added.** New semantics nodes, with their full description.
- **Nodes removed.** By identifier; no need to repeat full descriptions.
- **Nodes changed.** Identifier plus the field-level diff.

The diff is the agent's primary signal that its last action had an effect. Always included verbatim.

## 10. Action space

Actions are exposed as typed Dart functions, surfaced to the model as JSON-schema'd tools.

### 10.1 Action types

- `tap(node_id)` — tap a semantics node.
- `long_press(node_id)` — long-press a semantics node.
- `enter_text(node_id, text)` — focus and type into a text field.
- `scroll(node_id, direction, distance)` — scroll a scrollable. `node_id` is the scrollable.
- `scroll_until_visible(scrollable_id, target_id)` — convenience for off-screen content.
- `gesture(node_id, kind)` — pinch, swipe, custom. Discrete kinds, not arbitrary paths.
- `system_back()` — Android back button or equivalent.
- `wait(seconds)` — explicit wait, bounded; the harness rejects waits over 5s.
- `inspect_widget(node_id)` — request the widget tree for a semantics node. Consumes a turn.
- `done(reason)` — end the session voluntarily. Reasons: `goal_reached`, `goal_unreachable`, `stuck`.

Each action carries an optional `wait_strategy` field (see §7.3) declaring how the harness should stabilize before the next observation.

### 10.2 Action targeting

Actions target semantics node identifiers, not raw `Finder`s. The binding translates these to actual hit-test targets at execution time. This means:

- The model never produces coordinates or brittle text-match finders.
- Validation is mechanical: the harness checks the node ID exists in the current observation.
- Identifiers are stable across replays of the same session against the same build.

The semantics tree must include every interactable node the agent might touch. If a custom widget is interactable but not exposed semantically, it's invisible to the agent. This is a deliberate constraint — the agent operates at the same level as a screen reader, which is the right level for goal-directed behavior. Apps with poor semantics annotations will surface this loudly through the binding's diagnostics.

## 11. Memory: summary vs. diff

Two distinct memory artifacts, produced by different parties on different cadences for different purposes.

### 11.1 Running summary (model-authored, session-spanning)

The agent's accumulated knowledge of the app. Authored by the model — each turn, the model emits both an action and an updated summary. The harness enforces a soft length budget (~500 tokens) and rejects updates that exceed a hard cap (~1000 tokens), prompting the model to compress.

Structure is loose but typically covers:

- App identity and purpose
- Routes/screens visited and what they're for
- State that persists across screens (auth, selected items, etc.)
- Hypotheses formed and not yet confirmed
- Things tried that didn't work, to avoid repetition

The summary is the model's notebook. The harness does not edit it.

### 11.2 Per-turn diff (harness-authored, single-turn)

What changed between observations. Authored mechanically, included verbatim in the next prompt. Small (~200-500 tokens typical), fresh, uncontaminated by model interpretation.

The diff answers "what did my last action do?" The summary answers "what do I know about this app?" Different questions, different artifacts.

### 11.3 Last N actions

The last 3-5 actions verbatim, including the exact action and a one-line outcome. Older actions are folded into the summary.

## 12. Trajectory persistence

Every session writes a trajectory file (JSONL) containing:

- Session metadata: goal, AGENTS.md hash, build identifier, model identifier, harness version.
- One record per turn: observation, stability metadata, proposed action, validation result, executed action, diff, summary update.
- Final record: outcome (`done`, `budget_exhausted`, `harness_error`), final summary.

Trajectories are reviewable and structurally comparable. Full execution-level replay (the same action sequence producing the same observations) requires the controlled environment of `integration_test` and is a v2 concern (§11.4).

## 13. Use cases

### 13.1 Open-ended exploration

Goal: "explore this app and produce a structural map." The agent walks the app and produces a final summary describing its structure. Useful as documentation, onboarding artifact, or sanity check.

### 13.2 Goal-directed exploration

Goal: "find the page where I can change my password" or "complete a checkout with a single item." The agent navigates toward the goal and reports success, failure, or impasse.

### 13.3 Adversarial exploration

Goal: "try to produce a `RenderFlex overflow`" or "find a state that triggers an unhandled exception." A bug-finding fuzzer where the model selects edge-case inputs. v2.

### 13.4 Trajectory replay (v2)

Re-run a recorded action sequence against the app under `integration_test`, with stubbed time and network for determinism. Compare observations turn-for-turn. Drift becomes a regression signal. This use case is what justifies `integration_test` showing up in v2 — the same loop primitive applies, but the substrate is different because the goal is different (reproducibility, not fidelity to real-app behavior).

### 13.5 Trajectory collection for fine-tuning

Run many sessions, store trajectories, use as training data. Out of scope for the harness; the trajectory format is designed for it.

## 14. Model integration

### 14.1 Provider abstraction

A thin `ModelProvider` interface with implementations for: a local MLX-served OpenAI-compatible endpoint, Anthropic, OpenAI, and Google. Existing Dart packages (`dartantic_ai`, the per-provider SDKs) are candidates for the provider plumbing; the harness should not own this layer.

### 14.2 Constrained output

Every model call uses a JSON schema constraining output to `{action, summary_update, rationale?}`. Outputs that don't match are rejected and re-prompted (one retry, then the turn fails). This is essential for local models.

### 14.3 Primary target: Qwen3 35B-A3B at 8-bit on M3 Ultra

The harness is designed primarily around running against an MLX-served Qwen3 35B-A3B at 8-bit quantization, on a 96GB M3 Ultra:

- Memory footprint is comfortable (~35GB for weights, ample headroom for KV cache and context).
- Active-parameter count (~3B) keeps per-token latency in a usable range — first-token in the few-hundred-ms range, generation tens of tokens per second on this hardware.
- Qwen3's tool-calling and structured-output behavior is a good fit for schema-constrained action emission.
- MoE routing favors the kind of bounded-step pattern matching this loop produces ("given this observation, propose next action") over deep multi-step chain-of-thought.

### 14.4 Other model tiers

- Frontier (Claude, GPT-4 class via API): always works. Useful as benchmark and fallback for tasks where local stalls.
- 14B–32B dense (Qwen2.5-Coder-32B, etc.): viable alternative to the MoE on hardware without the M3 Ultra's memory; tradeoff is lower capability ceiling but more predictable behavior.
- 7B–13B: usable for narrow goal-directed tasks; not recommended for open-ended exploration.
- Below 7B: structured output works, exploration quality is poor.

The harness ships with sensible defaults for each tier (lower temperature for smaller models, more aggressive validation retries, smaller observation budgets).

## 15. Failure modes and handling

- **Stability policy budget expired.** Observation captured anyway, tagged with what's still busy. Not a failure; the model decides whether to wait or proceed.
- **Invalid action.** Up to 3 retries against the same observation with the validation error included. Failure counts as a failed turn.
- **Model returns malformed output.** One retry with the schema error included. Second failure counts as a failed turn.
- **Three consecutive failed turns.** End the session with `harness_error: agent_stuck`.
- **Runtime error in the app.** Captured in the observation but doesn't end the session; the agent should triage and recover. Sessions only end on errors that crash the Dart VM hosting the app.
- **VM service connection lost.** End the session with `harness_error: connection_lost`. The trajectory log is preserved up to the last successful turn.
- **Binding not initialized.** Detected on connect; the harness exits with a clear error pointing at the setup instructions.
- **Budget exhaustion.** Clean end with `budget_exhausted`. Final summary still produced.

## 16. v1 scope

### Ships in v1

- The `leonard_flutter` package: `LeonardBinding`, VM service extensions, frame-stability signal exposure, semantics tree capture, action execution.
- The `leonard_agent` harness: perception-action loop, stability policy implementation (action-relative, quiet-frame, bounded-stability), prompt construction, action validation, trajectory logging.
- Provider implementations for: local MLX (OpenAI-compatible), Anthropic, OpenAI.
- A CLI: `leonard_agent --goal "..." --vm-uri ws://... --model <name>`.
- A minimal AGENTS.md template.
- Open-ended and goal-directed exploration (§13.1, §13.2).

### Not in v1

- Adversarial exploration (§13.3).
- Trajectory replay under `integration_test` (§13.4).
- Multi-device parallel sessions.
- A web UI for browsing trajectories. CLI viewer is fine for v1.
- Trajectory-based fine-tuning pipelines (§13.5).
- Custom gestures beyond the discrete kinds in §10.1.
- Demonstration recording (a human user driving the app while the harness records the trajectory).
- Hot-reload-aware sessions (where the user reloads code mid-session and the agent picks up the new state).

## 17. Open questions

- For apps using `Navigator 2.0` declaratively, the route stack abstraction needs validation against a real sample app before v1 ships. The fallback may need design work.
- Should `inspect_widget` cost a full turn (consistent with the loop invariant) or be a free side-channel (more ergonomic)? Lean toward full turn for v1, revisit if it's a friction point.
- The binding registers with `FlutterError.onError`. Apps that already install custom error handlers will need a chaining strategy. Document the recommended pattern; consider a `MarionetteConfiguration`-style hook.
- Does the agent need a way to express "I want to wait for a specific thing to happen" (e.g., wait for a node with label X to appear)? Currently it can only request a `wait_strategy` for the next turn. This may be insufficient for screens with intentionally-long async loads.
- How aggressively should the diff compress? Repeated visits to the same screen produce highly redundant diffs.
- Should the harness expose a way to prompt the user for help when stuck (e.g., "I can't figure out how to log in, what credentials should I use?")? This blurs human-in-the-loop boundaries; v1 should probably omit and revisit.

## 18. Risks

- **`LeonardBinding` adoption friction.** Users have to add a package to their app and modify `main()`. This is the same friction Marionette accepts; it appears to be the unavoidable cost of operating against the real app.
- **Custom binding conflicts.** Users who want to also use `integration_test` will hit binding conflicts. Document the constraint clearly; possibly provide a separate `integration_test`-compatible mode in v2 for the replay use case.
- **Apps with poor semantics.** Without good semantics annotations, the agent operates blind. The binding should warn loudly at connect time when interactive widgets lack semantics, and provide configuration hooks for custom design systems.
- **Stability policy heuristics fail.** Action-relative policy may terminate prematurely on apps where actions take >800ms to produce visible effects (heavy network calls). The model can request longer waits via `wait_strategy`, but tuning the defaults will require empirical work.
- **Local model ceiling.** Even Qwen3 35B-A3B may not reliably handle long-horizon goal-directed exploration on complex apps. Mitigation: ship with frontier model support so the harness is useful regardless.
- **VM service stability.** The VM service surface evolves between Flutter releases. Pin a minimum Flutter version and track changes via the dart-lang/ai repo.

## 19. Success criteria

- A user can install the binding, modify their `main()`, run their app under `flutter run`, and start an exploration session in under 10 minutes.
- Qwen3 35B-A3B at 8-bit can complete the "log in, find a settings screen, change a setting, log out" task on a representative non-trivial app in <20 turns, ≥80% of attempts.
- The action-relative stability policy terminates within budget on ≥95% of post-action turns for a representative app, without missing observable changes.
- The harness produces a useful structural map of an unfamiliar app from a single open-ended exploration session — useful enough that a developer encountering the app for the first time would prefer it to reading the source.
- A 30-minute exploration session against a real running app produces a trajectory file under 50MB and reviewable in the CLI viewer in a single sitting.
