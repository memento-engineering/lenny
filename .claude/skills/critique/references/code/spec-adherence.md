---
name: spec-adherence
version: 1
---

## Summary

Spec-adherence measures whether the implementation diff does what the
bead's spec said to do — no more, no less, nothing contradictory. Read
the diff against the spec; every step in the spec's `## Implementation
Plan` should have a matching change in the diff, and nothing in the diff
should contradict a decision the spec recorded.

**What to read.** The diff: `git diff $(git merge-base main <branch>)..<branch>`
(the bead's worktree branch). The spec: the bead's `## Acceptance
Criteria`, `## Implementation Plan`, and `## Validation Plan` (from
`bd show <id>`). Cross-reference the two.

## Grades

### A
Every Implementation Plan step has a corresponding, recognizable change
in the diff. Acceptance criteria are all satisfied by the diff. Nothing
in the diff contradicts a recorded decision. A reader who knew only the
spec could have predicted this diff.

### B
The diff implements the plan, but one step's realization differs in a
minor, defensible way (a helper inlined, a rename) — the deviation is
visible in the diff and does not change behavior the spec specified.

### C
One Implementation Plan step is missing from the diff, or one acceptance
criterion is not satisfied, but the gap is small and self-contained — a
follow-up commit on the same branch would close it without a redesign.

### D
Multiple plan steps are missing or implemented differently in ways that
change specified behavior, or several acceptance criteria are unmet. The
diff is recognizably "the same bead" but does not deliver the spec as
written.

### F
The diff implements something orthogonal to the Implementation Plan, or
contradicts a decision the spec recorded. A reader holding the spec would
not recognize this diff as the bead. This is a respec-or-rebuild signal.

## Calibration
- If between A and B, err toward B when any step's realization differs
  from the literal plan, even harmlessly — A means the diff matches the
  plan, not merely "is fine".
- If between B and C, err toward C when an acceptance criterion is
  unsatisfied by the diff; an unmet criterion is never a B.
- If between C and D, err toward D when more than one plan step is
  missing, or a missing step blocks a downstream step.
- If between D and F, err toward F when the diff *contradicts* the spec
  (does the opposite of a recorded decision) rather than merely falling
  short of it.
- Out of scope: code style, test thoroughness (that's `test-coverage`),
  and whether the diff touched files outside the spec's surface (that's
  `scope-creep`). Grade only diff-vs-spec fidelity.
