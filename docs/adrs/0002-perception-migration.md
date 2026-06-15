# ADR 0002 — Perception migration: refactor behind the contract firewall

- **Status:** Accepted (strategy). Implements [ADR 0001](0001-declarative-perception-framework.md).
- **Bead:** `lenny-vf3r`
- **Related:** `lenny-jh3b` (design), `lenny-0d6v` (sink), `lenny-rps3` (diagnostics)

## Context

[ADR 0001](0001-declarative-perception-framework.md) adopts `perception`, a declarative perception
framework. This ADR records *how to get there from the code that exists today* without a big-bang
rewrite.

The key property: the **VM-service contract is a firewall.** `get_stable_observation`, the
handshake/manifest, the per-tool extensions, and the serialized `Observation` shape are consumed by
the harness; the perception engine that *produces* the Observation can be rebuilt behind that
contract without the harness noticing.

## Decision

Treat this as a **refactor behind a stable contract, migrated incrementally**, not a rewrite. Three
zones:

### Zone 1 — Untouched (the firewall holds)

The harness side barely moves; the model never sees the change:

- `leonard_agent`: `VmServiceClient`, `LeonardSession`, `ObservationPuller`, `LoopDriver`
  (the 10 steps), the model provider, validation, trajectory, conversation builder.
- `leonard_cli`, and the session plumbing in `leonard_devtools`.
- `ObservationDiffer` keeps working on the serialized tree (structural diff still diffs;
  element-authored diffs are a later optimization, not a migration requirement).

`get_stable_observation` is still the call — it just runs a different engine behind it.

### Zone 2 — Refactored / re-homed (reused, moved)

Most of `leonard_flutter`'s observation machinery survives, relocated into the owner pipeline:

| Today | Becomes | Reuse |
|---|---|---|
| `budgeted_json.dart` | the **serialize-under-budget** pass ("layout") | near-verbatim |
| `policy_loop` + `frame_stability_tracker` + `framework_busy_snapshot` | the `PerceptionOwner` **settle gate** + `FlutterFrameSettleSource` | policy logic reused |
| `semantics_capture.dart` | the **`core` extension's** data source | reused |
| `error_ring_buffer.dart` | the **sink's event buffer / `Digest`** pattern | pattern reused |
| extension registry | the owner's **root assembly** | reworked |
| `stability_metadata` / `observation_request` | stay (request/stamp contract) | as-is |
| `observation/models.dart` (harness-side typed `Observation`) | evolves depth-1 → **tree** | `fromJson` follows |

### Zone 3 — Net-new (where the real cost is)

The `perception` pure-Dart package: `Perception`, `StatelessPerception` / `StatefulPerception` /
`PerceptionState`, `PerceptionElement`, `PerceptionContext`, `InheritedPerception`,
`PerceptionOwner`, the leaf primitives (`Node` / `Field` / `Watch` / `Digest`), the `SettleSource`
interface, and the sink. Plus `PerceptionAnchor` (Flutter adapter) and the diagnostics integration
(`lenny-rps3`).

**The expensive, bug-prone heart:** the keyed reconciler (mount/update/unmount by identity) and the
`InheritedPerception` dependency-tracking + invalidation are a *mini-Flutter* — the machinery
Flutter took years to harden. Weeks, not days. Extracting `PerceptionOwner` out from under the
`WidgetsBinding` singleton (today `LeonardBinding` *is* a `WidgetsBinding`) is real surgery.

## The contract change every extension author feels

```dart
// today
Future<Map<String, Object?>?> observe(ObservationContext ctx);
// tomorrow
Perception build(PerceptionContext ctx);
```

`tools` and `onActionExecuted` stay (action half parked, ADR 0001 §3). `busyState()` folds into the
settle gate. First customers: `leonard_dio`, `leonard_riverpod`, `leonard_router` —
small, and the proof the authoring model works. `router` exercises `PerceptionAnchor` first
(Flutter nav); dio and riverpod-core are pure-Dart-friendly.

## Package topology shift

```
            perception   (pure Dart core)
            ▲      ▲      ▲
  perception_flutter   leonard_dio   leonard_riverpod  ...
  (Flutter adapter)
            ▲
     the app under test
```

Today this is inverted — `leonard_flutter` holds everything app-side and Flutter is load-bearing
at the bottom. Renaming `leonard_flutter → perception_flutter` (and the rest of the suite) is
**deferred cosmetic churn**, kept separate from the architectural extraction.

## Migration sequence (no big-bang cutover)

**Dual-path coexistence.** The binding runs legacy `observe()->fragment` extensions **and** new
`build()->Perception` extensions simultaneously, both merged into the serialized `Observation`; the
handshake manifest marks which extensions are perception-native.

1. Extract the `perception` core (the hard net-new reconciler) with its own tests, no app wiring.
2. Stand up `PerceptionOwner` inside `LeonardBinding` alongside the existing fragment path.
3. Convert one extension (a leaf like `dio`, or `core`) to `build()->Perception`; assert the serialized
   output is equivalent to the old fragment. Use `assertObservationEquivalent(legacyJson, perceptionJson)` from
   `package:leonard_flutter/test_support/observation_equivalence.dart` (lenny-lwiy) as
   the conversion gate — golden baselines committed in
   `packages/leonard_flutter/test/goldens/`.
4. Migrate extension-by-extension behind the dual path.
5. Retire the fragment path last; `observe()` is removed from the contract.

The harness never notices, because of the firewall.

## Risks

- **The reconciler is a mini-Flutter** — the highest-risk net-new code; budget accordingly.
- **Owner-from-binding extraction** — Flutter bindings are mixin-heavy singletons; clean separation
  is non-trivial.
- **Serialized `Observation` depth-1 → tree** affects (a) `ObservationDiffer` and (b) **how the
  model reads structure** — an open prompt-rendering question: does deeper structure help the model,
  or just cost tokens? Validate empirically during step 3 before committing the tree shape.

## Addendum — genesis cutover & the external dependency edge (lenny-wisp-5h5, 2026-06-14)

This ADR was written assuming `perception` would be extracted into an **in-repo** package
(Zone 3, "extract the `perception` core … with its own tests, no app wiring"). That step is
**superseded**: perception was instead extracted *out* of lenny entirely into
`memento-engineering/genesis` (the genesis campaign, `lenny-s9jd`), rebuilt on the domain-free
`tree` spine. lenny now **consumes** it rather than housing it.

- **The edge:** `leonard_flutter` depends on `genesis_perception` via a **pinned git
  dependency** (`git@github.com:memento-engineering/genesis.git`, `ref: 41ec0ec`,
  `path: packages/perception`). The ref is pinned (not floating) because genesis is actively
  churning (sibling packages `tree`/`taxonomy`/`typesetting`/`dialogue`/`consent`).
- **Mandatory `genesis_tree` override:** `genesis_perception` declares `genesis_tree: any` under
  `resolution: workspace`. From outside the genesis workspace, pub resolves that sibling to
  pub.dev (where it does not exist) and version-solving fails. The transitive `genesis_tree` is
  therefore pinned to the same git ref via `dependency_overrides` in the lenny **workspace-root**
  pubspec (overrides are only honoured at the root).
- **Barrel rename:** the public import is `package:genesis_perception/genesis_perception.dart`
  (the old in-repo path was `package:perception/perception.dart`).
- **API delta:** genesis rebuilt perception on the `tree` spine with A12 subclass mechanics, a new
  `Field` leaf, and an A9 conformance delta. The full ledger lives in genesis
  `docs/CONFORMANCE-DELTA.md`; downstream migration beads (`lenny-lwiy`, extension conversions) must
  account for it.

Net effect on the migration sequence: ADR step "extract the core" is replaced by "wire the
external edge" (this bead). The dual-path coexistence strategy (below) is unchanged — it now runs
against an imported `genesis_perception` instead of an in-repo one.

## Consequences

- `lenny-0d6v` (sink) becomes `PerceptionElement.markNeedsHarvest` — first-class, not bolted on.
- `lenny-rps3` (diagnostics) is part of the core + adapter.
- Implementation epics/tasks are filed when build starts; this ADR records the *strategy*, not the
  schedule.
