---
name: test-coverage
version: 1
phase: code
on_grade:
  D: { verdict: revise, hint: rebuild }
  F: { verdict: revise, hint: rebuild }
---

## Summary

Test-coverage measures whether the diff's net-new behavior is exercised
by tests, and whether the bead's `## Validation Plan` checks are runnable
and pass against the branch.

**What to read.** The diff: `git diff $(git merge-base main <branch>)..<branch>`.
The spec: the bead's `## Acceptance Criteria` and `## Validation Plan`.
Where the Validation Plan names commands, run them against the branch. lenny's
canonical test command is `melos run test` (`dart test` on pure-Dart packages,
`flutter test` on Flutter packages).

## Grades

### A
Every net-new function/behavior in the diff has at least one test path
that exercises it (success and, where it matters, the error path). The
Validation Plan's commands run and pass. New edge cases the diff
introduces have negative tests. Widget-level behavior added to a Flutter
package has at least one `flutter test` widget/golden test.

### B
Net-new behavior is tested, but one edge case or error path the diff
introduces lacks an explicit test. The happy path and the Validation
Plan are covered; a corner is left to integration coverage.

### C
About half the net-new behavior has tests; the rest is untested but
low-risk (a thin wrapper, a constant, a string). The Validation Plan
runs but one item is not actually checked by an assertion.

### D
Most net-new behavior is untested. A test file may have been touched but
it does not exercise the new code paths. The Validation Plan has commands
that don't map to assertions.

### F
No tests added for net-new behavior, or `melos run test` does not pass
against the branch. This is a rebuild signal — the bitsmith reads the
findings on re-claim.

## Calibration
- If between A and B, err toward B when any error path the diff adds has
  no negative test — A requires the failure modes be exercised, not just
  the happy path.
- If between B and C, err toward C when fewer than half of the diff's new
  functions/methods are named in a test.
- If between C and D, err toward D when a touched test file does not
  actually call the new code (coverage theatre).
- If between D and F, err toward F when `melos run test` fails on the
  branch, or zero tests were added for genuinely new behavior.
- Out of scope: whether the diff matches the plan (`spec-adherence`) or
  whether existing tests still pass after unrelated changes
  (`regression-risk`). Grade only coverage of *this diff's* new behavior.
