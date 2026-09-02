---
status: accepted
date: 2026-09-01
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a4-core-done-is-gated-by-a-scenario-declared-reason-form
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A4"
---
## A4 (2026-09-01) — `core.done` is gated by a scenario-declared reason form

**Decision:** a scenario file may declare a `done-reason-pattern: <regexp>`
line; the launcher passes it to the driver as `--done-reason-pattern`, and
`ActionValidator` gains a fourth pass that rejects a `core.done` whose `reason`
does not match, with `reason: 'done_reason_mismatch'`. The rejection rides the
existing `decideAndValidate` validator-retry budget (3 retries) — no second
retry mechanism is introduced. The outer objective is renamed **Mission** in
the operating guide and in the system-prompt section header, so "Goal" names
only a field inside the app under test.
**Why:** the 2026-09-01 panel self-drive run ended in a premature `core.done`
because the panel's text field is labelled `Goal` while the operating guide
called the outer objective the Goal; the scenario's prose requirement for the
reason form was unenforced. A mechanical check turns a silent false success
into a retried turn.
**Affects (if promoted):** `leonard_agent`'s `ActionValidator` contract (a
validator built without a pattern is unchanged), `leonard_cli`'s argument
surface, `packages/leonard_cli/templates/AGENTS.md` + `kDefaultAgentsMd`, and
the `## Mission` system-prompt header. **Status:** pending.

---

