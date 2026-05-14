---
name: critique
description: >
  Grade ONE bead against ONE rubric in isolation. The Committee member —
  dispatched by `/deliberate` once per rubric in the active set so grades
  don't anchor on each other. Returns a schema-validated JSON object with
  rubric, version, grade (A–F), and rationale.
---

# Critique

Grade a single bead against a single rubric in **isolation** so the grade reflects the rubric, not your accumulated conversation context.

## Dispatch

Run `fs critique <id> --rubric <name>`. Parse the single JSON line on stdout. Branch on `via`:

- `via=fs_agent`, `ok=true`: worker ran; the JSON output is on stderr/captured upstream.
- `via=fs_agent`, `ok=false`: worker failed; surface `error` and stop.
- `via=subagent`: dispatch via the Agent tool with the envelope's `subagent_type`, `description`, and `prompt`.
- `via=none`: surface `error` verbatim and stop.

Never execute the critique process body in this conversation.

## Worker Contract

When dispatched as a subagent, the critique member's job is:

1. Read the bead: `bd show <id>`.
2. Read the rubric reference file named in the dispatch prompt (that one rubric). Do **not** read any other file in that `references/` directory except `output-schema.json` — peer rubric texts would anchor the grade on cross-rubric context this grader is not supposed to have.
3. Verify the bead against the world. Use Grep/Glob/Read to confirm that file paths and symbols cited in the bead actually exist in the repo (or are explicitly marked as new). Use `bd show <related-id>` and `bd search <terms>` to confirm sibling, parent, and ADR claims. The rubric tells you what to verify; this step is how you verify it.
4. Grade the bead against the rubric on an A–F scale. Cite a specific element of the bead — and, where the rubric requires it, a specific result of step 3 — in the rationale.
4a. **Re-deliberation check.** If `bd comments list <id>` shows any prior comment whose body begins with `inspector: REBUILD.`, `inspector: RESPEC.`, or `inspector: DECOMPOSE.` (the canonical Circuit Breaker prefixes; see `skills/inspect/references/process.md` §131-158), this is a re-deliberation round. Compute the bead's branch as `fs/<id>/<sanitized-title>` (the sanitization rule lives in `internal/project/project.go::BranchForBead`: lowercase, non-alphanumerics stripped, truncated to 40 chars). Run `git diff $(git merge-base main <branch>)..<branch>` and read the verdict comment. Treat the diff and the verdict as evidence for **this** grading round — your rubric's Calibration section tells you how to weigh it. The isolation rule on rubric texts still holds: do **not** read any other `*.md` file in that `references/` directory. The re-deliberation evidence is the branch and the verdict comment, not a sibling rubric's text.
5. Emit exactly one JSON object on stdout matching the output-schema path named in the dispatch prompt:

   ```json
   {"rubric": "<name>", "version": <int>, "grade": "A|B|C|D|F", "rationale": "<one sentence>"}
   ```

No surrounding prose, no labels, no comments side effects, no edits to the bead.

## What This Skill Doesn't Do Itself

This skill body is a **dispatcher**. The grading work lives in the per-rubric reference files under `references/<rubric>.md` plus the agent definition at `agents/critique.md`. The dispatcher never executes grading directly; one of the three tiers (`fs_agent`, `subagent`, or `none`) always handles it.
