# ADR 0001 — Perception: a declarative perception framework for Dart

- **Status:** Accepted (design). Implementation strategy in [ADR 0002](0002-perception-migration.md); not yet built.
- **Bead:** `lenny-jh3b`
- **Companions:** `lenny-0d6v` (heartbeat sink), `lenny-rps3` (diagnostics dogfooding), [ADR 0002](0002-perception-migration.md) (migration)
- **Tagline:** *Lenny — Dart's Perception Framework.*

## Context

Lenny's perception is already a tree — it's just depth-1 and reconciled the dumb way. `Observation`
is the root; each extension's `ExtensionFragment` is a child; `observe() -> JSON` assembles it
imperatively; `ObservationDiffer` reconciles by brute structural compare.

While exploring modeling **butane** (a federated Flutter BLE plugin, `../butane_flutter`) as a
extension, four loose ends each turned out to be the *same* problem Flutter already solved in its
build pipeline:

- the heartbeat event sink (`lenny-0d6v`),
- the streaming-characteristic "when is it settled" question,
- action validation ("does the target node exist?"),
- token budgeting (`budgeted_json.dart`).

Four unrelated problems collapsing into one borrowed mechanism is the tell that the shape is
*discovered*, not invented.

## Decision

Adopt a Flutter-modeled, declarative perception framework named **`perception`**. Perception
becomes a pure function of app state:

```
AppState ── build ──▶ Perception tree ── harvest ──▶ Observation
   (Flutter:  State ── build ──▶ Widget tree ── layout/paint ──▶ pixels)
```

Reconcile by **identity (keys)**, not structural diff. Dirty via a **sink** (= `markNeedsBuild`).
Serialize under **token budget** (= layout constraints). The framework is **pure Dart**; Flutter
is an optional adapter.

## Naming & positioning

- **`Perception`** — the immutable config node (the `Widget` analog).
- **`perception`** — the pure-Dart core package.
- This separates concerns: **`perception` is a reusable layer that multiple consumers read** — the
  Leonard agent, the human DevTools inspector, and butane — rather than something the agent owns.
  The agent is one consumer, not the center.

## The two trees (not three)

| Flutter | Perception | Notes |
|---|---|---|
| **Widget** (immutable config) | **`Perception`** | promotes `observe()->JSON` into `build(context) -> Perception`; composes + nests |
| **Element** (mounted, persists) | **`PerceptionElement`** | owns the live subscription, resident snapshot, identity, context; really a `StreamBuilder`/`ListenableBuilder` |
| **RenderObject** (retained) | *rejected* — the serialized `Observation` is a per-turn **projection** | JSON is cheap + disposable; cross-turn identity via stable id on the element |
| **BuildContext / InheritedWidget** | **`PerceptionContext` / `InheritedPerception`** | ambient values flow down without prop-drilling — a parallel mechanism, never the same type |
| **Keys + `canUpdate`** | keyed reconciliation | the diff is a byproduct of mount/update/unmount, not a structural compare |
| **BoxConstraints / layout** | token budget (`budgeted_json`) | budget down, serialized size up, prune on overflow |

## The Perception API surface

The hierarchy carries over almost verbatim:

```dart
abstract class Perception {
  const Perception({this.key});
  final PerceptionKey? key;
  PerceptionElement createElement();
  static bool canUpdate(Perception a, Perception b) =>
      a.runtimeType == b.runtimeType && a.key == b.key;
}

abstract class StatelessPerception extends Perception {   // pure composition
  const StatelessPerception({super.key});
  Perception build(PerceptionContext context);
}

abstract class StatefulPerception extends Perception {    // subscription + resident snapshot
  const StatefulPerception({super.key});
  PerceptionState createState();
}

abstract class PerceptionState<T extends StatefulPerception> {
  void initState();              // subscribe to the live source
  void didChangeDependencies();  // re-read InheritedPerception
  Perception build(PerceptionContext context);
  void dispose();                // cancel subscription
  void perceived(VoidCallback fn);  // == setState: mutate resident state + markDirty (the SINK)
}
```

**Authors rarely subclass either** — like Flutter devs reach for `Text`/`Row`/`ValueListenableBuilder`
over raw `StatefulWidget`. The framework ships the primitives; authors compose them:

- `Node(name, {children, key})` — named container in the output. **Multichild.**
- `Field(name, () => value, {level})` — leaf emitting one value, read **synchronously** from
  resident state. `level` is a `DiagnosticLevel`.
- `Watch<T>(listenableOrStream, (v) => Perception)` — subscribe, hold latest resident, rebuild
  subtree on emit. The common subscription path; the sink entry point.
- `InheritedPerception<T>(value, child)` — provide ambient `T` down the tree; **emits no node**.
- `Digest(source, summarize)` — high-rate sources: emit a rolling summary (rate, last value)
  rather than every event.

`build` returns a **single** `Perception`; multichild is a keyed `Node` — keying discipline is
enforced exactly where dynamic lists are built. `Node`/`Field`/`InheritedPerception` being the only
things that emit (or not) is what makes the Observation tree **sparser** than the Perception tree —
the RenderObject-is-sparser-than-Widget property, with zero retained tree.

Authoring example (butane), and the migration it replaces:

```dart
// TODAY:  Future<Map<String,Object?>?> observe(ObservationContext ctx)  → a JSON fragment
// TOMORROW:
class BlePerception extends StatelessPerception {
  const BlePerception(this.manager);
  final CentralManager manager;

  @override
  Perception build(PerceptionContext context) => Node('ble', children: [
    Field('adapterState', () => manager.state.name),
    Watch(manager.connections, (conns) => Node('connections', children: [
      for (final c in conns) BleConnection(c, key: ValueKey(c.peer.id)),  // keyed!
    ])),
  ]);
}
```

## Lifecycle: `harvest → build → serialize`

Per-turn frame, walked top-down (harvest a node, build it — now its children are known —
reconcile, recurse):

- **`harvest()`** — **synchronous (Decisions §1):** snapshots resident/subscribed state, never
  `await`s. This is the step Flutter does not have, because Flutter is *push-only*. Push sources
  (BLE notifications, `ChangeNotifier`s) route through the **sink** (`markDirty` == `setState`) and
  never harvest; pull sources (semantics tree, route, GATT snapshot) are read — that read *is*
  harvest.
- **`build(context)`** — pure; reads the just-harvested snapshot; returns children; reconcile by
  key. Identical to Flutter `build`.
- **serialize** — emit Observation JSON under token budget (`budgeted_json` == constraints).

## The scheduler: `PerceptionOwner` and two clocks

A `BuildOwner` analog that fuses `BuildOwner` + `PipelineOwner` + a sliver of `SchedulerBinding`
(our pipeline is cheap and single-pass). It is **not** just Flutter's BuildOwner because of two
clocks Flutter collapses into one (vsync) and we cannot:

- **App clock** (fast, internal): app state changes — widget frames, sink events. The owner holds
  the dirty set; `scheduleHarvestFor(element)` is `markNeedsBuild`, called by the sink and the
  bridge.
- **Agent clock** (slow, external): the agent calls `get_stable_observation`. *This* triggers the
  harvest walk.

`get_stable_observation(policy)` → `PerceptionOwner.harvestStableFrame(policy)`: (1) await settle —
the gate is the union of *widget pipeline idle* ∧ *no dirty perception elements* ∧ *extension
`busyState` idle* ∧ *event quiet-window elapsed*; (2) walk harvest→build→serialize; (3) return the
`Observation`.

**Subtlety (real hang risk):** a dirty perception element must call `scheduleFrame()` on the
binding. If a sink event dirties a perceptor but nothing in the widget tree changed, no frame fires
and a settle loop waiting on frame callbacks stalls. Flutter never hits this because `setState`
*is* what schedules the frame.

The owner is **pull-driven now, push-ready later**: the dirty-set + settle machinery is identical
whether the agent pulls or we notify on settle-after-dirty (`lenny-0d6v` v2 — interrupt the agent).

## `PerceptionContext` vs `BuildContext`

The unifying rule, applied at every Flutter touchpoint:

> **Tree-agnostic foundation utilities** (`Diagnosticable`, key-like value types) → reuse directly.
> **Anything tied to the widget tree** (`BuildContext`, `WidgetInspectorService`,
> `SchedulerBinding`, the tree itself) → **reimplement the mechanism over our tree; never reuse
> Flutter's type.**

`BuildContext` is a handle into the *widget* tree; `PerceptionContext` into the *Perception* tree.
**Same role, different tree — which is the precise reason they must be different types.** The shared
shape is the trap; unifying them couples the core to Flutter and kills the pure-Dart goal.

```dart
// package:perception  —  ZERO flutter imports, runs in any Dart isolate
abstract class PerceptionContext {
  PerceptionId  get id;                                   // stable identity
  PerceptionKey? get key;
  T? dependOnInheritedPerceptionOfExactType<T extends InheritedPerception>();
  void markNeedsHarvest();                                // the sink, from inside
  // NOTHING about widgets, render objects, sizes, or BuildContext.
}
```

| | `BuildContext` | `PerceptionContext` |
|---|---|---|
| Handle into | widget/element tree | Perception/PerceptionElement tree |
| Owned by | `BuildOwner` (Flutter) | `PerceptionOwner` (pure Dart) |
| Lookup | `dependOnInheritedWidgetOfExactType` | `dependOnInheritedPerceptionOfExactType` |
| Invalidates | `updateShouldNotify` → dirty widget element → frame | `updateShouldNotify` → dirty perception element → re-harvest |
| Requires | Flutter | nothing — pure Dart |

`PerceptionElement implements PerceptionContext` (as `Element implements BuildContext`), a *parallel*
implementation of the same reactive mechanism with zero Flutter underneath. **Values cross the
bridge; contexts never do.**

## The bridge: `PerceptionAnchor`

A Flutter-only widget the app developer drops in to mark an opt-in seam. It reads `BuildContext` and
writes resident → `InheritedPerception` — the only place both contexts coexist:

```dart
// package:perception_flutter — the ONLY file where both contexts are in scope
class _PerceptionAnchorState extends State<PerceptionAnchor> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AppBleScope.of(context);          // BuildContext read  (Flutter side)
    _handle.provide(InheritedPerception(session));    // value crosses; the CONTEXT does not
  }
}
```

A `BuildContext` read produces *resident data* that becomes an `InheritedPerception` on the
perception side — read at widget-build time (the push moment, satisfying §1), resident thereafter.
No perceptor ever holds a `BuildContext`. In pure Dart there is no anchor; perceptors provide
`InheritedPerception` directly. **`InheritedPerception` is the universal ambient mechanism; the
anchor is just a Flutter-specific source feeding it.**

## Pure-Dart core & package topology

```
            perception   (pure Dart core — Perception, PerceptionContext, owner, sink, SettleSource)
            ▲      ▲      ▲
  perception_flutter   leonard_dio   leonard_riverpod  ...
  (adapter: FlutterFrameSettleSource,
   core semantics extension, PerceptionAnchor)
            ▲
     the app under test
```

- The **core** is pure Dart, mountable in any isolate: `Perception`, `PerceptionElement`,
  `PerceptionContext`, `InheritedPerception`, `PerceptionOwner`, the walk, the dirty set + sink, the
  `SettleSource` interface, VM-service-extension registration (`dart:developer`, not Flutter).
- The **Flutter adapter** is the only Flutter-coupled layer: a `WidgetsBinding`-backed
  `FlutterFrameSettleSource` (frame idleness), the `core` semantics extension, and `PerceptionAnchor`.
- Settle source diverges cleanly: `FlutterFrameSettleSource` vs `EventLoopSettleSource`
  (microtask/timer drain) for a headless program. The `quiet-frame` `StabilityPolicy` is
  Flutter-only; `bounded-stability` generalizes.

DevTools clarifications (so "pure-Dart DevTools harness" isn't a contradiction): DevTools attaches
to *any* VM service (a `dart run --observe` CLI has one); the DevTools extension being Flutter-web
runs *inside DevTools*, not the target, so it can drive a non-Flutter target.

## Inspectability (diagnostics)

Reuse Flutter's **foundation-level** `Diagnosticable`/`DiagnosticableTree` utilities where they pay
(`toStringDeep` dumps, `DiagnosticsProperty`, `DiagnosticLevel`, `DiagnosticsNode.toJsonMap` over
our own extension). It is **not free** (hand-written `debugFillProperties`, our own serialization +
panel) and we do **not** mirror `Widget`/`Element` contracts or ride the widget inspector
(`WidgetInspectorService` is widget-bound). Scoped in `lenny-rps3`.

## Mechanism unification (why the analogy is structural)

- **sink (`lenny-0d6v`) == `markNeedsBuild`.**
- **A 50 Hz notify characteristic == a widget that `setState`s every frame** — coalesce + sample a
  `Digest`; do not wait for silence.
- **action validation == hit-testing** the Perception tree.
- **token budget == `BoxConstraints`.**

## The three roles ("agent" is overloaded)

1. **Author (human):** constructs `Perception` classes — the only place they're written.
2. **Owner/runtime (`PerceptionOwner`):** mounts, schedules, runs harvest→build→serialize.
3. **The model (LLM):** *consumes* the serialized Observation, emits actions — never constructs
   `Perception`s. From the harness side, `harvestStableFrame` simply replaces the fragment-merge as
   the Observation source; the `loop_driver` 10 steps are untouched.

The one seam where the model touches perception-as-config is **attention** — steering an ambient
`PerceptionPolicy` (collapse/expand subtrees, reprioritize budget) that flows down as
`InheritedPerception`, making `build` a function of *(app state, agent focus)*. The model still
doesn't author; it turns a wheel the authors wired. **Parked** with the action half.

## Decisions & forks

**Decided**

1. **Harvest is synchronous; async-is-an-action.** *(locked 2026-06-09)* Perception reflects only
   resident/subscribed state; anything that must go fetch (one-shot GATT read, HTTP) is an
   **action**, not perception. Keeps a frame a synchronous pure function of resident state and
   pre-draws the perception/action boundary. *Consequence:* pull sources must be kept resident via
   a subscription; a genuinely poll-only source with no change signal is polled-to-keep-resident —
   a per-source concern, deliberately not a framework one.
2. **Identity lives on the element tree — no retained third tree.** *(locked 2026-06-09)* Stable id
   issued at `mount`, a consequence of keyed reconciliation. A render-tree analog is held in reserve
   only as a budgeting-performance escape hatch (incremental re-serialization on very large trees),
   element-attached before a separate tree. *Real lever:* keying discipline. *Inspectability* via an
   on-demand diagnostics projection (`lenny-rps3`), not a persistent tree.

**Parked**

3. **The action/affordance half** — dynamic, state-derived tool lists harvested from the tree, and
   model **attention** (above). Companion ADR. Fork §1's "async-is-an-action" line pre-draws its
   boundary. Today's flat handshake-time tool registry stays unchanged.

## Migration

See [ADR 0002](0002-perception-migration.md). It's a refactor behind the VM-service contract
firewall — the harness is essentially untouched; the work concentrates app-side and migrates
incrementally via dual-path coexistence.

## Provenance

Cross-repo design exploration: running butane as a `perception` extension. butane registers
`ext.butane.*` for its own standalone surface; the adapter re-exposes it as
`ext.flutter.exploration.butane.*`. Reference for the sink is butane's `subscribe` → `notification`
event channel (`butane_harness` `central_role.dart`).
