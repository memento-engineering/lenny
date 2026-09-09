---
status: accepted
date: 2026-09-09
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: nightly-mutation-replaces-per-pr-sweep
  surfaces:
    - ".github/workflows/ci.yaml"
    - "tool/select_mutation_files.sh"
  obsoletes: []
  updates:
    - a3-mutation-strategy-vends-through-leonard-assets
  obsoleted-by: null
  updated-by: []
  bead: lenny-f2z4
  legacy-id: null
---

# Nightly mutation replaces the per-PR sweep

## Context

The changed-file mutation lane delayed pull-request completion without gating
merges. It also ran red by construction during dry sizing, as documented by
`lenny-no3n`. The scheduled failures observed before this decision predated
that fix, and the cancelled schedule after the fix did not establish a green
nightly baseline.

Removing the per-PR lane would otherwise remove all mutation signal for
`leonard_flutter`, because its full suite does not fit the nightly time budget.
A nightly selector can preserve bounded, change-focused Flutter mutation while
also rotating through unchanged production files over time.

## Decision outcome

Mutation runs only in scheduled or manually dispatched nightly workflows.
`leonard_native` and `leonard_contract` retain their full sweeps.
`leonard_flutter` retains its existing local runner through
`tool/run_mutation_pilot.sh`, but its capped diff selection moves behind
`tool/select_mutation_files.sh` in the nightly matrix and gains a deterministic
rolling slice. An empty combined selection is a successful, explained skip.

This decision updates
`a3-mutation-strategy-vends-through-leonard-assets` only where A3 placed the
Flutter sweep in the CI `mutation-pr` matrix. A3's asset-vending strategy and
its pure-Dart/Flutter runner fork remain in force.

## Consequences

- Pull requests no longer wait for an ungated mutation sweep after coverage.
- The nightly retains full pure-Dart signal and restores bounded Flutter
  signal, including periodic coverage of files outside the latest diff.
- Mutation regressions are reported nightly or after an explicit manual
  dispatch rather than on the pull request that introduced them.
