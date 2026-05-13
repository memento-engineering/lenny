---
name: deliberate
description: >
  Convene the Committee on a bead. The chair runs in THIS (parent)
  session — it asks `fs deliberate <id>` for one critique dispatch
  envelope per rubric in the active rubric set, dispatches all of them
  as /critique subagents in a single Agent turn so each member grades
  in isolation, aggregates the schema-validated grade JSON, and writes
  `rubric_set=<set>@v<int>` plus per-rubric `grade:<rubric>=<A-F>@v<int>`
  labels via `fs deliberate-apply`. Idempotent; fail-closed on a bad
  grade. Does NOT route — that's `fs route`'s job. With no `<id>`, runs
  the driver: enumerate committee_review ∪ convene-eligible in_spec via
  `fs ready --committee` and drive each through convene → chair →
  `fs route --apply`, sequentially.
---

# Deliberate

Convene the Committee on a bead. **The chair runs in this conversation** — it
is a parent-level orchestrator, exactly like `/marshal`'s body.
The members (`/critique`, one per rubric) are the subagents; the chair
dispatches them. Never nest: a subagent cannot dispatch subagents.

The full chair cycle lives in `references/process.md`. Load and follow it.

`/deliberate <id>` deliberates one bead. `/deliberate` with no argument
(or `/deliberate --auto`) runs the **driver**: `fs ready --committee` to
enumerate every bead needing deliberation (`committee_review` ∪
convene-eligible `in_spec`), then for each — sequentially — convene if
needed, run the chair cycle, and `fs route --apply`. See the
`## --auto mode (the driver)` section of `references/process.md`.

## What This Skill Does NOT Do

- **Grade rubrics itself** — it dispatches `/critique` members.
- **Route** — choosing the next status (`ready` / `spec_review` / `draft`)
  and builder capabilities is `fs route <id>`, run after deliberation.
- **Write labels directly** — all label writes go through `fs deliberate-apply`.
- **Run the members in-process** — if you can't dispatch the `/critique`
  subagents, BLOCK (see `references/process.md`); do not read all the
  rubric texts and grade sequentially.
