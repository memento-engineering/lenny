---
name: regression-risk
version: 1
---

## Summary

Regression-risk measures whether landing this diff is safe for everything
the diff was *not* about. The full test suite passes, lint is clean, and
no existing public surface changes behavior. A diff that adds a feature
but breaks an unrelated subsystem — or leaves the suite red — is high
risk regardless of how good the new code is.

**What to read.** The diff: `git diff $(git merge-base main <branch>)..<branch>`.
Run `go test ./...` and `gofmt -l .` (and any project lint the
Validation Plan names) against the branch. The spec: the bead's
`## Validation Plan` for the canonical check commands.

## Grades

### A
`go test ./...` passes, `gofmt -l .` reports nothing, project lint is
clean. No behavioral change to any existing exported symbol. The diff is
purely additive or strictly local; nothing downstream can break.

### B
Suite and lint are green, but the diff changes an existing internal
helper in a way that *could* affect a caller — and the callers are
updated and tested, so the risk is contained but non-zero.

### C
Suite and lint are green, but the diff changes an existing exported
symbol's behavior in a small way that callers must adapt to, and not
every caller is obviously covered. A latent break is plausible.

### D
Lint is dirty (`gofmt -l .` lists files, or project lint errors), or a
flaky/skipped test masks a real change, or an exported contract changed
without a migration note. The branch needs work before it's safe.

### F
`go test ./...` fails, or the diff breaks an unrelated subsystem, or it
changes a published contract that other beads depend on with no
migration. Landing this breaks main — a human is needed.

## Calibration
- If between A and B, err toward B when the diff modifies any existing
  function body (not just adds new ones) — A is for additive/local diffs.
- If between B and C, err toward C when an exported symbol's behavior
  changes and a caller in another package is not visibly updated.
- If between C and D, err toward D when `gofmt -l .` is non-empty or
  project lint reports any error — a dirty tree is never better than C.
- If between D and F, err toward F when `go test ./...` fails on the
  branch, or a contract other beads depend on changed without a
  migration — those are land-breaks-main, the `blocked` tier.
- Out of scope: coverage of the *new* behavior (`test-coverage`) and
  whether the diff matches the plan (`spec-adherence`). Grade only the
  blast radius on everything else.
