# ADR 0000 — AI decision register

**Status:** Living document — never Accepted, never closed.
**Rule (adopted from the_grid ADR-0000, Nico, 2026-06-11):** any decision made by AI lands here as an amendment and **stays here** until Nico promotes it (into its own ADR, or a named amendment of an existing one) or shoots it down. AI must not write its own decisions directly into ADR 0001+; those documents record human-ratified decisions only.

Entry format: `A<n> (date) — title` · Decision · Why · Affects · **Status:** pending | promoted → ⟨where⟩ | rejected.

**Substrate split (2026-06-11):** the substrate-level decisions from the founding conversation (schema-codegen, A2UI wire format, render backends, the projection/manipulation substrate) **moved to `engineering.memento/genesis` ADR-0000** (genesis A1–A8) when that repo was created — `perception` is migrating to genesis as a `tree` consumer. lenny's register now holds only **lenny-as-testing-harness** decisions. *(Note: ADR 0001/0002 — the perception design + migration — logically follow `perception` to genesis once the code physically moves; not done yet.)*

---

## A1 (2026-06-11) — Registration composes with the extension contract; catalog search parked

*(was A5; renumbered after the substrate entries migrated to genesis)*
**Decision:** node/catalog registration (genesis A2's codegen registry) must compose with lenny's **extension contract** — concretely the pure-Dart **`exploration_contract`** package (`plugin.dart` / `types.dart` / `registry.dart` / `plugin_context.dart`), the seam by which extensions contribute their own node vocabularies + schemas + `ext.exploration.*` surfaces. Retrieval/**search** over a large catalog (progressive-disclosure / RAG) is **parked** — eat the context now, optimize later.
**Why:** the catalog will be multi-extension and grow; registration is where extension vocabularies join genesis's codegen'd core registry. Search is real but premature; context budget is acceptable at current scale.
**On-disk reality (verified 2026-06-11):**
- the extension contract == the `exploration_contract` extraction — **bead `lenny-wisp-9h557`** (CODE_REVIEW), the_grid M0 prerequisite (the_grid ADR-0001 D6).
- the namespace rename `ext.flutter.exploration.*` → `ext.exploration.*` — **bead `lenny-wisp-41rdl`** (READY).
- the **package + terminology rename** (`exploration_*` → `leonard_*` and `plugin` → `extension`): **bead `lenny-4tvb`** (P1, release blocker), created 2026-06-11.
**Affects (if promoted):** genesis A2's registry; `exploration_contract`'s `registry.dart`; the terminology sweep. **Status:** pending.
