# Genesis substrate — spike handoff (2026-06-11)

Self-contained context for a fresh **Fable + Ultracode** session to plan and run the de-risking spikes. The canonical decision record is the two ADR-0000 registers linked below — read them first; this brief just orients.

## What this is
memento's agentic software-engineering platform: **`the_grid`** = building, **`lenny`** = testing. New substrate repo **`memento-engineering/genesis`** holds:
- **`tree`** — the node/element/keyed-reconcile engine extracted from Flutter (domain-free).
- **`perception`** — the measurement domain on `tree` (migrating here from lenny).
- Consumers: `lenny` (tester, via perception) + `the_grid` (platform SDK).

## Decision record (read first)
- genesis register: `<genesis>/docs/adr/ADR-0000-ai-decision-register.md` (A1–A8)
- lenny register: `docs/adrs/0000-ai-decision-register.md` (A1)
- perception design: `docs/adrs/0001-declarative-perception-framework.md` (+ `0002-perception-migration.md`)
- grid (sibling) ADRs: `<the_grid>/docs/adr/` (0000 register, 0001 foundations, 0002 projections, 0003 reconciler, 0004 tmux runtime)

## Blessed (decided)
- **Substrate factoring + two-axis model** (genesis A1). Authoring axis = measurement (read-only) / expression (read-write). Rendering axis = model-facing (serialize, no geometry) / machine-facing (typed structs) / human-facing (render tree, 2-D geometry).
- **`tree` spine** (genesis A8). `Seed` (immutable config) → `Branch` (mounted, persistent). `TreeContext` is a **separate** handle passed to `build()` — `Branch` does **NOT** implement it (sheds Flutter's `Element ≡ BuildContext` "original sin"). `TreeOwner` = scheduler.
- **Schema-first + codegen; no `dart:mirrors`** (genesis A2). One schema = Dart factory registry + LLM tool/JSON schema. Runs on every Dart target.
- **A2UI flat-keyed wire format** (genesis A3), scoped to the authoring axis. `tree` keys == A2UI component IDs; whole-subtree emission reconciles to a patch by key.
- **Multiple render backends; "the window is an embedder choice"** (genesis A4), scoped to the rendering axis.
- **House conventions** (genesis A6): freezed sealed unions + exhaustive `switch`, `build_runner`, predictable-flutter layering, Fakes-not-mocks.

## Parked / open
- Catalog search/RAG — **parked** (eat context for now).
- Multi-party consensus on a rejected write — **parked, leaning `setState`** (last-write-wins).
- **Open** (genesis A7): grid's structural snapshot-diff vs genesis keyed reconcile — do bead domains eventually mount as `tree` nodes?

## Constraint for THIS phase
**Spike first.** No commits, no concrete ADRs, no production scaffolding yet — genesis stays ADR-only until the spikes green-light the approach. `perception` and `leonard_flutter` still physically live in **lenny**, so **the spikes run in lenny**, not in the (code-empty) genesis repo.

## Spikes (each names the genesis entry it de-risks)
1. **Headless-Flutter render-tree dump** — a `flutter test` in `leonard_flutter`, pump a widget, dump `debugDumpRenderTree()` to stdout. Proves the full framework runs in a shell with no window. *(A4 oracle · ~½ day)*
2. **Bare-VM ANSI cell grid** — a `dart run` scratch, box-grid via a double-buffered cell diff → ANSI. Proves the VM render surface, zero engine. *(A4 Fork B · ~1 day)*
3. **Schema + codegen round-trip, one node** — take `perception`'s `Node`/`Field` → schema → codegen registry + tool schema → deserialize an A2UI `surfaceUpdate` back into a tree → reconcile by key. Run identically on the VM and under `flutter test`. *(A2 + A3 · ~1–2 days)*
4. **Tree → terminal, end-to-end** — wire spike 2's backend to a live `Watch`-driven tree via the owner's dirty set. *(A4 · after 1–3)*
5. **A2UI action round-trip (setState flavor)** — emit a surface with an `action`, fire it, route it back as an intent that invalidates one node. Smallest probe of validation/invalidation. *(A5 · informs the parked consensus call)*

Spikes **1 and 2 are independent — start in parallel.**

## Suggested order
1 + 2 (confidence) → 3 (the load-bearing schema/wire proof) → 4 → 5. **After green:** scaffold genesis (pub workspace + `tree`/`perception` skeletons + `CLAUDE.md` carrying the register rule), migrate `perception`, then promote register entries A1–A8 to genesis ADR-0001+.

## Recall prompt
> Read `docs/genesis-spike-handoff.md` and the two ADR-0000 registers it links. Plan and run the de-risking spikes — spike-first, no commits/scaffolding/ADRs. Start spikes 1 and 2 in parallel.
