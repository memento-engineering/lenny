---
name: factory-process
description: One factory turn — run the /deliberate --auto driver, then one /marshal cycle, then report. Sequences the two existing drivers; re-implements neither.
---

# Factory — Process

One invocation = one factory turn. Idempotent; safe to loop. The two
work-doing steps are the *existing* drivers — run them exactly as their
skills define them. `/factory` adds only the sequencing and the report.

```
1. DELIBERATE-AUTO  -> run /deliberate's --auto driver over every bead needing deliberation
2. MARSHAL CYCLE    -> run one /marshal cycle (Step 0 SYNC included)
3. REPORT           -> per-bead deliberation outcomes + the marshal cycle summary (single-shot only)
```

## 1. Deliberate-auto

Run the `/deliberate --auto` **driver** exactly as defined in
`skills/deliberate/references/process.md` → `## --auto mode (the
driver)`. Do not re-implement it here. In brief, that driver:

1. `fs ready --committee` — enumerates, one ID per line, every bead in
   `committee_review` plus every convene-eligible `in_spec` bead (all
   `blocks`-deps closed ∨ recorded). **Beads labelled
   `calibration-baseline` are already excluded** by `fs ready
   --committee` (factoryskills-d15x) — `/factory` inherits that; add no
   extra guard, and do not re-add the parked baseline beads. Empty list
   → nothing to deliberate; proceed to Step 2.
2. For each ID, **in order, sequentially**: `bd show <id>` →
   `fs convene <id>` if it is `in_spec` → run the deliberate **chair
   cycle** in *this* conversation (parent-level orchestrator, UNCHANGED
   — `/factory` does not nest a subagent that dispatches subagents; the
   chair fans out the `/critique` members itself, exactly as in
   `/deliberate`) → `fs route <id> --apply`. One bad bead does not abort
   the run — record it and move on.

Collect each bead's route outcome for the Step 3 report.

## 2. Marshal cycle

Run **one** cycle of `skills/marshal/references/process.md`, start to
finish, **Step 0 SYNC included** (`git pull --rebase --autostash` —
refreshes `.beads` and any merged skill/binary changes; the
deliberate-auto step above may have moved beads to `ready` that the
marshal's Step 1 SCAN must see). Do not re-implement the cycle; follow
that file. The marshal cycle handles its own dispatch, monitoring,
review dispatch, merge-on-APPROVED, and Step 5c notifications.

## 3. Report

- **Loop mode** (`/loop 10m /factory`): suppress this report. The
  marshal cycle's Step 5c notifications are the only output. Detect loop
  mode the same way `/marshal` does — the parent does not request an
  inline report.
- **Single-shot** (`/factory` once): print
  1. one line per deliberated bead: `<id>: <route outcome>` (or
     `<id>: BLOCKED — <reason>`), then `deliberated: N`;
  2. the marshal cycle summary verbatim (the block from
     `skills/marshal/references/process.md` Step 6).

If both steps were no-ops, say so: `Factory turn complete. Nothing to
deliberate; nothing to build.`

## Block Explicitly

`/factory` itself blocks only if it cannot run a step at all (e.g.
`fs` not installed, `/deliberate` or `/marshal` skill missing). Per-bead
problems are handled inside the drivers (the chair's
`deliberator: BLOCKED/...` comments, the marshal's UNFIT/ESCALATED
comments) — surface them in the report, do not abort the turn.

## Return

`COMPLETE` (with the report above) or `BLOCKED` (with the reason a step
could not run).
