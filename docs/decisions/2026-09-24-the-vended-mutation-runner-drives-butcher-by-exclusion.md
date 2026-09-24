---
status: accepted
date: 2026-09-24
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: the-vended-mutation-runner-drives-butcher-by-exclusion
  surfaces:
    - "packages/leonard_cli/lib/assets/tools/leonard/run_mutation.sh"
    - "tool/butcher_excludes.dart"
    - "tool/butcher_report_summary.dart"
    - "tool/aggregate_mutation_shards.sh"
    - "tool/empty_mutation_shard.sh"
    - "packages/leonard_contract/pubspec.yaml"
    - "packages/leonard_native/pubspec.yaml"
  obsoletes: []
  updates:
    - a3-mutation-strategy-vends-through-leonard-assets
  obsoleted-by: null
  updated-by: []
  bead: lenny-mbgq
  legacy-id: null
---

# The vended mutation runner drives butcher, and selects files by exclusion

## Context

A3 vends one pure-Dart mutation runner through `leonard_cli`'s tool assets and
describes its implementation as shell orchestration over each consumer's
`mutation_test` dev dependency. That engine is a regex rewriter with no
compile-error category: any non-zero exit counts as a detection, so every
non-compiling mutant scores as a kill, and it never separates an uncovered
mutant from a surviving one. The printed grade therefore carries an upward bias
and a downward one at once and is not a measurement of test quality.

Measured on `leonard_native` at one source revision, the AST engine produced
499 mutants — 324 killed, 78 survived, 91 uncovered, 6 not compiling — for
65.72 percent, 80.60 percent over covered code, in 2 minutes 44 seconds.
`mutation_test` produced 542 mutants and 327 detected for 60.3 percent, grade
C, in 22 minutes 6 seconds. That engine is now `butcher`, published from an
org repository, which is what makes this adoptable rather than a personal fork.

## Decision

- The vended runner's engine is `butcher`. Its interface is unchanged: the
  same three modes, the same flags, the same positional file list, the same
  Flutter refusal, the same artifact paths and the same opt-in gating. Only
  the body changed.
- Per-file selection is expressed as a generated exclusion. butcher's
  configuration is exclude-only — one `exclude` glob list in a `butcher.yaml`
  at the project root, with no include list and no negation — so the runner
  enumerates the package's library sources, subtracts the selected set, and
  writes the remainder. The file belongs to one run: it is generated, never
  committed, and removed by a trap even when the run is interrupted, and a
  configuration the tool did not write is never overwritten.
- The report is the Stryker JSON document butcher writes. Everything that read
  the regex engine's console summary or its five report filenames — the dry
  sizing, the shard aggregate and the `leonard_native` rebaseline verifier —
  reads that document instead.
- `leonard_flutter` stays on `mutation_test` through
  `tool/run_mutation_flutter.sh` until butcher grows a runner seam for
  `flutter test`. The pilot already forks on package type, so the split needs
  no new mechanism, and the shard aggregate accepts either engine's shards
  while refusing a download that mixes them.
- Both engines must not sit on the pure-Dart path: `mutation_test` comes out
  of `leonard_contract` and `leonard_native` in the same change, so nothing
  can fall back to it silently.

## Consequences

- The score means something: uncovered mutants are reported separately and
  lower the mutation score without touching the covered-code score, and
  non-compiling mutants are their own category rather than kills.
- Two flags could not ride through unchanged. `--test-impact` keeps its
  meaning — route each mutant to the tests that reach it — but butcher
  collects that routing itself, so the flag now drops the supplied lcov
  instead of generating input documents. `--rules` described semantic rules
  butcher has no seam for and is refused with a diagnostic rather than
  accepted and ignored.
- The baseline moved into the engine. butcher verifies a green suite before it
  mutates anything, so the runner no longer runs its own baseline suite; a red
  one still stops the run before the scored phase whether or not gating is on.
- The sharding decision is untouched: the nightly still selects files, shards
  by file and aggregates per package, with the same job names and the same
  artifact layout.

## Rejected

- Keeping both engines on the pure-Dart path behind a switch: a silent
  fallback to the tool whose grade is not a measurement is worse than a loud
  failure.
- An include list in the runner: butcher's configuration is exclude-only by
  decision, and reproducing an include semantics on top of it would give two
  answers to one question.
