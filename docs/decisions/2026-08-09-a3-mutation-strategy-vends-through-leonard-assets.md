---
status: accepted
date: 2026-08-09
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a3-mutation-strategy-vends-through-leonard-assets
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A3"
---
## A3 (2026-08-09) — Mutation strategy vends through Leonard assets

**Decision:** The org's pure-Dart mutation runner is a deterministic tool asset bundled by `leonard_cli` and installed at `tool/leonard/run_mutation.sh`. Consumers pass package, repository, coverage, and repeatable semantic-rule paths; builtin generated rules remain enabled. Runs size first, report every format under the consumer repository, and do not gate scores unless requested.
**Why:** This reuses the working package-asset install channel, avoids copy drift, and does not couple the runner to the deferred `leonard_grid_assets` Command/Seed package. A published runner package remains unnecessary while the implementation is shell orchestration over each consumer's `mutation_test` dev dependency.
**Affects:** `leonard_cli` vended assets, `tool/run_mutation_pilot.sh`, and pure-Dart consumers such as grid_engine. The vended runner is pure-Dart-only and rejects Flutter packages with exit 65; lenny's own pilot forks on package type so `leonard_flutter` keeps its existing local Flutter mutation path and stays in the CI `mutation-pr` matrix.
**Status:** pending.

---

