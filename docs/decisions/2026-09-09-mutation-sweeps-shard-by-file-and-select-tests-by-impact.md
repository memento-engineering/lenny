---
status: accepted
date: 2026-09-09
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: mutation-sweeps-shard-by-file-and-select-tests-by-impact
  surfaces:
    - ".github/workflows/ci.yaml"
    - "tool/test_impact.dart"
    - "tool/aggregate_mutation_shards.sh"
    - "tool/run_mutation_pilot.sh"
    - "packages/leonard_cli/lib/assets/tools/leonard/run_mutation.sh"
  obsoletes: []
  updates:
    - a3-mutation-strategy-vends-through-leonard-assets
    - nightly-mutation-replaces-per-pr-sweep
  obsoleted-by: null
  updated-by: []
  bead: lenny-jo57
  legacy-id: null
---

# Mutation sweeps shard by file and select tests by impact

## Context

`mutation_test` pays for one package test command per mutant. Measurement on
`leonard_flutter` showed 11.16 seconds for its 156-test directory and 11.32
seconds for all 213 tests: roughly 11 seconds was fixed compilation and startup
and only about 0.3 seconds was suite execution. The Ubuntu runner took roughly
27 seconds per Flutter mutant. Restricting Flutter test paths therefore does
not materially reduce a mutant's cost. The pure-Dart packages have lower but
still meaningful per-mutant costs: approximately 2.4 seconds for
`leonard_native` and 0.6 seconds for `leonard_contract`.

The nightly already has one source-file selector and coverage-backed, ungated
mutation reporting. Parallelism must compose with that selector and preserve a
single package-level artifact for downstream mutation-health ingestion.

## Decision outcome

Nightly mutation work is partitioned only by selected source file. The matrix
uses six shards for `leonard_flutter`, three for `leonard_native`, and one for
`leonard_contract`. `tool/select_mutation_files.sh` remains the only selector;
it runs once per package and shard jobs consume modulo slices of its recorded
output. Pure-Dart selections still expand to every tracked `lib/**/*.dart`
file, while Flutter keeps its capped diff plus rotating selection. Shards never
split mutant ranges.

Each shard retains dry sizing and coverage input, then publishes a short-lived
report. An always-running aggregate job validates every expected shard, sums
its Found, Total, Undetected, and Not-covered counts, combines each per-file
Markdown section once, and publishes the canonical 14-day
`mutation-PACKAGE-full` artifact.

For pure-Dart packages only, each selected source is paired with the sorted
tests that transitively import it through same-package `package:` or relative
directives. The engine receives that mapping as one input XML document per
source, keeping impact discovery independent from `mutation_test`. A source
that exports another library is treated as a barrel and runs the full suite;
an unreferenced source also runs the full suite. Flutter continues to use its
whole-suite command because its measured cost is fixed startup, not test body.

## Consequences

- File-level matrix parallelism reduces nightly wall time without relying on a
  mutation-engine range feature.
- Pure-Dart mutants avoid unrelated tests when the import graph gives a safe,
  non-barrel match; conservative fallbacks prevent a missing edge from
  silently declaring a mutant uncovered.
- Coverage normalization, builtin and custom semantic rules, mutation
  operators, dry sizing, and reporting-only score policy remain unchanged.
- Downstream consumers continue to receive exactly one canonical artifact per
  package per nightly run.
