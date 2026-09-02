---
status: accepted
date: 2026-09-01
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a5-core-done-is-additionally-gated-by-an-observed-evidence-p
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A5"
---
## A5 (2026-09-01) — `core.done` is additionally gated by an observed-evidence predicate

**Decision:** a scenario file may declare a `done-evidence-pattern: <regexp>`
line alongside A4's `done-reason-pattern`; the launcher passes it to the driver
as `--done-evidence-pattern`, and `ActionValidator` gains a fifth pass that
rejects a `core.done` when no node `label` or `value` in the current
observation matches it (`reason: 'done_evidence_missing'`), and — when the
pattern has capture groups — when the action's `reason` does not quote every
captured token of some matching row as a standalone word
(`reason: 'done_evidence_mismatch'`). Both rejections ride the existing
`decideAndValidate` validator-retry budget; no second retry mechanism is
introduced. The panel scenario's pattern is character-for-character the
`rowPattern` in `tool/verify_panel_selfdrive_receipt.dart`, so the in-loop gate
and the receipt verifier accept the same rows.
**Why:** A4's reason form is a claim about the world, not evidence of it — the
2026-09-01 round-6 run satisfied the reason regex with a fabricated
`panel smoke passed: inner turn 1 tool start_command` while the observation
carried no Timeline row at all. A predicate over the observation makes the
claim checkable against what the driver can actually see.
**Affects (if promoted):** extends A4; `leonard_agent`'s `ActionValidator`
contract (a validator built without a pattern is unchanged), `leonard_cli`'s
argument surface, and `packages/leonard_cli/scenarios/leonard_devtools_panel.md`.
**Status:** pending.
