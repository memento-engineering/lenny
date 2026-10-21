---
status: accepted
date: 2026-10-20
decision-makers:
  - "Nico Spencer"
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: a-run-fails-only-when-leonard-drove-the-app-everything-else-is-infra
  surfaces:
    - "packages/leonard_cli/lib/src/run_verdict.dart"
    - "packages/leonard_cli/lib/src/run.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: lenny-guy4.1
  legacy-id: null
---

# A run fails only when Leonard drove the app; everything else is infra

## Context and Problem Statement

lenny#177 asks for a gate contract: exit 0 pass, 75 infrastructure, anything
else fail. `leonard_cli` exits 0 for every non-error termination, including a
run that spends its whole budget without reaching the goal, so its exit code
cannot be that contract. Gas City 1.5.0 reserves exit 75 for a check that
could not reach its infrastructure (`GateInfraExitCode`). Its spec says such a
check re-runs without spending an attempt, but a formula's `[steps.check]`
runs on the ralph path, which fails on 75 like any nonzero exit (confirmed
live by `tool/gc_pack_e2e.sh`). Any other nonzero exit sends the coding agent
back to change its code.

## Decision Outcome

* **The classifier lives in `leonard_cli`, in Dart** (`run_verdict.dart`),
  not in a pack script. Ruled by Nico in chat, 2026-10-20. `--summary-json`
  carries `verdict`, `reason` and a turn `digest`. `--gate-exit-codes` exits
  0 pass, 75 infra, 1 fail. Without the flag, exit codes are unchanged.
* **The rule (agent):** `pass` is `done` with every golden matched. `fail`
  needs evidence about the app: the budget ran out short of `core.done`, the
  VM service went away after at least one turn, or a frame missed its golden.
  Everything that kept Leonard from judging the app is `infra`: no launch or
  attach (zero turns), `config_error`, `inference_latency`, `agent_stuck`,
  `observation_envelope_rejected`, `unclassified`, and a usage error.
* `agent_stuck` is infra even when the provider answered. Three invalid
  actions in a row say the model failed, not the app. Calling it a fail would
  send a coding agent to fix an app that may be fine.

### Consequences

* Good, because any gate (the Gas City pack, the_grid, a CI step) gets the
  same verdict from one tested function.
* Bad, because in Gas City 1.5.0 an infra verdict still fails the workflow.
  Only `leonard.verdict=infra` on the bead, not the workflow outcome, tells it
  from a real failure.
* Neutral: a model that gives up but still calls `core.done` passes. Scenarios
  that need proof should set `--done-evidence-pattern`.
