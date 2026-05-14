---
name: deliberate-process
description: Full Committee chair cycle — read the bead, fan out one /critique member per rubric, aggregate the grade JSON, fail-closed on a bad grade, apply labels via fs deliberate-apply, print the summary. Does not route.
---

# Deliberate — Process

You are the Committee chair. The chair runs in **this (parent) conversation** —
it is a parent-level orchestrator, exactly like `/marshal`'s body.
The members (`/critique`, one per rubric) are the subagents you dispatch.
Never nest: a subagent cannot dispatch subagents. If you cannot dispatch the
`/critique` members, BLOCK (see "Block Explicitly"); do **not** read all the
rubric texts and grade them sequentially in this context — that cross-rubric
anchoring is the exact failure mode the isolated-member design exists to prevent.

Each invocation grades one bead. The cycle is idempotent — safe to re-run.

## Inputs

- The bead id (e.g. `factoryskills-abc`).
- The active rubric set, chosen from the bead's status: `spec_review` →
  `skills/deliberate/references/rubric-set.json` (`spec-readiness@v2`, six
  rubrics — `concreteness`, `decision-density`, `scope`, `prior-art`,
  `coherence`, `decisions`); `code_review` →
  `skills/deliberate/references/code-review-rubric-set.json` (`code-review@v1`,
  five rubrics — `spec-adherence`, `test-coverage`, `scope-creep`,
  `regression-risk`, `prior-art`). Each rubric carries its own version pin
  independent of the set version. `fs deliberate <id>` emits the right set's
  envelopes; the `/critique` member reads exactly the rubric path its envelope
  names (which may be under `references/code/`).

## Cycle

1. **Read the bead.** `bd show <id>` — confirm its status is
   `spec_review` **or** `code_review`. If the bead cannot be found, or is
   in neither, BLOCK/dependency. (The status also selects the rubric set —
   see Inputs; `fs deliberate <id>` does that selection for you.)

2. **Get the critique envelopes.** `fs deliberate <id>` — parse the JSON
   **array** on stdout. Each element is a critique dispatch envelope
   (the same shape `fs critique <id> --rubric <name>` emits). Branch on each
   element's `via`:
   - `via=fs_agent`, `ok=true`: the member already ran via `fs agent` — its
     grade was printed to **stderr** by the child process, not returned here.
     Nothing to dispatch for this rubric.
   - `via=fs_agent`, `ok=false`: BLOCK/member with the element's `error`.
   - `via=subagent`: collect this envelope for dispatch in step 3.
   - `via=none`: BLOCK/dependency with the element's `error` (it names
     `critique`, `fs init`, and `agent_endpoint`).

3. **Dispatch the members — in one Agent turn.** Dispatch every
   `via:subagent` envelope **in a single Agent-tool turn with multiple
   invocations** (one `Task`/Agent call per envelope, all in one message), so
   members run concurrently and each reads only its named rubric file. Use
   each envelope's `subagent_type` (`critique`), `description`, and `prompt`
   verbatim. Each member returns one JSON object on stdout matching
   `skills/critique/references/output-schema.json`:
   `{"rubric": "<name>", "version": <int>, "grade": "A|B|C|D|F", "rationale": "<one sentence>"}`.

4. **Aggregate.** Read the set name and version from the rubric-set file
   the bead's status selected — `rubric-set.json` (`{"rubric_set":"spec-readiness","set_version":2,...}`)
   for a `spec_review` bead, `code-review-rubric-set.json`
   (`{"rubric_set":"code-review","set_version":1,...}`) for a `code_review`
   bead — then build the canonical aggregate JSON:
   ```json
   {
     "rubric_set": "<set-name>",
     "set_version": <int>,
     "grades": [
       {"rubric": "<name>", "version": <int>, "grade": "A|B|C|D|F"},
       ...
     ]
   }
   ```

5. **Fail closed.** If any member returns malformed JSON, a missing grade, or
   a grade not in `A|B|C|D|F`, run
   `bd comments add <id> "deliberator: BLOCKED/member. <which rubric, what went wrong>" --actor deliberator`
   and exit **without writing any labels**.

6. **Apply labels.** Pipe the aggregate to `fs deliberate-apply <id>`:
   ```bash
   echo "$AGG_JSON" | fs deliberate-apply <id>
   ```
   `fs deliberate-apply` computes the idempotent diff and runs the necessary
   label remove/add calls itself — re-running is a no-op; stale `grade:*` and
   prior `rubric_set=*` labels are removed before the new ones are added.
   Capture stdout for the summary. The chair writes labels **only** through
   `fs deliberate-apply` — never by editing labels directly.

7. **Print the summary.** Emit one screen on stdout:
   ```
   bead: <id>
   rubric_set: <set-name>@v<set-version>
   <rubric>: <letter>@v<version>
   <rubric>: <letter>@v<version>
   ...
   ```
   Do **not** print a routing decision line. Routing is `fs route`'s separate
   responsibility — it produces `(next_status, capabilities[])` from the
   labels this chair writes.

## --auto mode (the driver)

`/deliberate` with no `<id>` (or `/deliberate --auto`) runs the **driver**:
it walks every bead that needs deliberation and drives each one through
the full cycle above, then routes it. The chair cycle (steps 1–7) is
unchanged — `--auto` just calls it once per bead.

1. **Enumerate.** `fs ready --committee` — prints, one ID per line, every
   bead in `spec_review`, every bead in `code_review`, plus every `in_spec`
   bead whose `blocks`-deps are all satisfied (closed ∨ recorded) and is
   therefore convene-eligible. Beads labelled `calibration-baseline` are
   intentionally parked (the dogfood calibration anchor) and excluded from
   this list. If the list is empty, report `COMPLETE — no beads to
   deliberate` and stop.

2. **For each ID, in order, sequentially** — finish one bead's entire
   deliberation (convene → all N rubric members → aggregate → apply →
   route) before starting the next. Do **not** fan out all beads × all
   rubrics in one Agent turn: members for *one* bead run concurrently
   (that is step 3 of the chair cycle), but beads themselves are serial.
   For bead `<id>`:
   a. `bd show <id>` — if its status is `in_spec`, run `fs convene <id>`
      (→ `spec_review`). If it is already `spec_review` **or** `code_review`,
      skip the convene (`code_review` beads arrive there via `fs done`). If
      it is anything else (a race — another worker moved it), skip the bead.
   b. Run the chair cycle on `<id>` exactly as documented above (steps
      1–7): `fs deliberate <id>` → dispatch the `/critique` members in one
      Agent turn → aggregate → fail-closed check → `fs deliberate-apply` →
      print the per-bead summary. If the chair BLOCKs on this bead, record
      it and move to the next bead — one bad bead does not abort the run.
   c. `fs route <id> --apply` — applies the routing matrix to the labels
      the chair just wrote. The matrix is phase-specific: a `spec_review`
      bead routes to `ready` / `in_spec` / `draft` (or self-loops on
      `spec_review` for a `human` outcome); a `code_review` bead routes
      per the code-phase matrix (approved → status held for `fs merge`,
      rebuild → `ready`, `regression-risk==F` → `blocked`, human-ultimatum
      → `code_review` self-loop). The chair never picks the next status;
      `fs route` does.

3. **Report.** One line per bead: `<id>: <route outcome>` (or
   `<id>: BLOCKED — <reason>`), then `COMPLETE`.

This driver is what the `/factory` wrapper skill (bead `factoryskills-w1z5`)
calls; `fs ready --committee` feeds it the same way `fs ready --auto` feeds
the marshal's cycle.

## Note: human capability outcomes

Grades may, in combination with the routing matrix in `fs route`, surface a
`human` capability outcome — a self-loop on the deliberation status
(`spec_review` for a spec bead, `code_review` for a code-phase bead) that signals
the AI committee couldn't decide and a human must rule. The trigger is a
grade-spread of 3+ letter steps between any two rubrics (e.g.
concreteness=A, decision-density=F). You don't decide capabilities (the
matrix does); your job is to grade rubrics honestly. If you notice grades
disagreeing strongly across rubrics, that's a feature — the routing matrix
will surface it as a human ultimatum.

## Block Explicitly

When you cannot complete a deliberation:
```bash
bd comments add <id> "deliberator: BLOCKED/<category>. <specific reason>" --actor deliberator
```
Then exit without writing any labels. Categories:
- `dependency` — bead missing, in neither `spec_review` nor `code_review`,
  the rubric set is unreadable, or `fs deliberate` is not installed (a
  `via:none` element).
- `member` — a `/critique` member returned malformed JSON or a non-A–F
  grade, or the `fs deliberate` array carried a `via:fs_agent ok:false`
  element.
- `ergonomic` — tooling gap (e.g. `fs deliberate-apply` not on PATH).

## Return

Report one of: `COMPLETE`, `BLOCKED`. Include the bead id and a
one-sentence summary.

## Note on `fs route --verdict`

`fs route <id> --apply --verdict <next_status>` is a human-only override
that promotes a bead in the deliberation status (`spec_review` / `code_review`)
to one of its valid targets without consulting the matrix and without
requiring grade labels. The chair
never uses this flag — its job is to grade and write labels; routing is
`fs route`'s domain. The flag exists so a human can promote a bead without
running the committee end-to-end (e.g. when grades are obviously unnecessary).
