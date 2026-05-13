---
name: factory
description: >
  Turn the whole factory one notch: run the `/deliberate --auto` driver
  (grade + route every `committee_review` and convene-eligible `in_spec`
  bead), then run one `/marshal` cycle (build → review → merge), then
  report. The operator entrypoint for autonomous operation —
  `/loop 10m /factory`. A thin sequencer: it calls `/deliberate` and
  `/marshal` as-is and re-implements neither, and touches no CLI, the
  deliberate chair, `fs route`, or the lifecycle.
---

# Factory

One turn of the factory: **deliberate-auto → marshal cycle → report.**
`/factory` is a *sequencer* — it runs `/deliberate`'s `--auto` driver
and `/marshal`'s cycle exactly as those skills define them. It
re-implements neither and modifies neither; it does not touch the
`fs` CLI, the deliberate chair, `fs route`, or the lifecycle state
machine.

The full cycle lives in `references/process.md`. Load and follow it.

## Operator Entrypoint

```
/loop 10m /factory
```

Claude Code's `/loop` takes one command, so `/factory` is the single
command that turns both halves of the factory — the Committee half
(`/deliberate`) and the marshal half (`/marshal`). Per ADR 0005 §5.

In loop mode the report (Step 3) is suppressed; the marshal cycle's
own Step 5c notifications are the only output. Single-shot
(`/factory` once) prints the full report.

## What This Skill Does NOT Do

- **Re-implement the deliberate driver** — it invokes `/deliberate`'s
  `--auto` mode (see `skills/deliberate/references/process.md`,
  `## --auto mode (the driver)`).
- **Re-implement the marshal cycle** — it runs one cycle of
  `skills/marshal/references/process.md` (Step 0 SYNC included).
- **Modify `/deliberate`, `/marshal`, the deliberate chair, `fs route`,
  or the lifecycle** — `/factory` only *sequences* them.
- **Add a `calibration-baseline` guard** — `fs ready --committee` already
  excludes those parked beads (factoryskills-d15x); `/factory` inherits it.
