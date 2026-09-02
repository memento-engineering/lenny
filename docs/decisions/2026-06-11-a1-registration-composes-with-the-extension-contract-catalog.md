---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a1-registration-composes-with-the-extension-contract-catalog
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A1"
---
## A1 (2026-06-11) — Registration composes with the extension contract; catalog search parked

*(was A5; renumbered after the substrate entries migrated to genesis)*
**Decision:** node/catalog registration (genesis A2's codegen registry) must compose with lenny's **extension contract** — concretely the pure-Dart **`leonard_contract`** package (`extension.dart` / `types.dart` / `registry.dart` / `extension_context.dart`), the seam by which extensions contribute their own node vocabularies + schemas + `ext.leonard.*` surfaces. Retrieval/**search** over a large catalog (progressive-disclosure / RAG) is **parked** — eat the context now, optimize later.
**Why:** the catalog will be multi-extension and grow; registration is where extension vocabularies join genesis's codegen'd core registry. Search is real but premature; context budget is acceptable at current scale.
**On-disk reality:**
- the extension contract is the `leonard_contract` extraction.
- the namespace rename `ext.flutter.exploration.*` → `ext.leonard.*`.
- the package + terminology rename to the `leonard_*` packages and `extension` terminology — completed.
**Affects (if promoted):** genesis A2's registry; `leonard_contract`'s `registry.dart`. **Status:** pending.

---

