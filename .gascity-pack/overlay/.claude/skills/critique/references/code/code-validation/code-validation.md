---
name: code-validation
version: 1
phase: code
gating: true
on_grade:
  F: { verdict: block }
---

## Summary

Code-validation is a gating rubric. It runs BEFORE the parallel grading members
and short-circuits the rest on an F grade. It has two mandates: (1) execute every
command in the bead's `## Validation Plan` inside the bead's worktree, and (2)
independently spot-check the diff for obvious structural breaks — the correlated-
failure mitigation (the architect authored the Validation Plan; this member runs it
in isolation).

lenny is a Dart **melos workspace** (`lenny_workspace`). The canonical
validation commands are the melos scripts in `pubspec.yaml`:

- `melos run analyze`  → `dart analyze` across the workspace (the Dart
  type/compile gate — there is no separate build step).
- `melos run test`     → `dart test` on pure-Dart packages + `flutter test` on
  Flutter packages.
- `melos run format`   → `dart format --output=none --set-exit-if-changed .`

**What to read.** The bead's `## Validation Plan` (from `bd show <id>`).
**Where to run.** The bead's worktree, provided in the `worktree_path` field of
your dispatch envelope. Change into that directory before executing any command.
Workspace resolution (`dart pub get` / `melos bootstrap`) is handled by the
worktree's setup hook; if a command fails for a missing `.dart_tool/`, that is a
setup break, not a code break — note it rather than failing the diff on it.
**What to run.** Each `→ exact command →` item in the Validation Plan.

## Grades

### A
Every Validation Plan command exits 0 and its output matches the expected result.
The diff spot-check reveals no obvious structural break (missing files that the plan
references, analyzer errors in newly-added libraries, test files with no test body).

### B
All Validation Plan commands pass, but the spot-check surfaces a minor gap —
e.g., a file the plan references exists but is empty. The gap is cosmetic and
would not cause `melos run analyze` to fail.

### C
One Validation Plan command exits non-zero but the failure is isolated — an
optional lint check, a test for a feature not yet implemented in this diff. The
core analyze + test commands pass.

### F
Any of the following:
- `melos run analyze` reports an analyzer error in the worktree (undefined
  symbol, type error, missing import — Dart's compile gate).
- `melos run test` exits non-zero in the worktree.
- One or more Validation Plan commands exit non-zero.
- The diff spot-check reveals a structural break that would cause the above failures.

Grade A/B/C when passing; F when failing. The strict default for D is escalate (per
yd9 strict-default rule), but code-validation's pass/fail binary means D should not
arise in practice — if unsure, grade F and let `block` stop the line.

## Calibration
- Grade F, not C, if `melos run analyze` reports an **error** (not a warning/info)
  — a non-analyzing diff is never C. The analyzer is lenny's compile gate.
- Grade F, not C, if `melos run test` fails — a red test suite is never C.
- Grade B only when ALL commands pass but the spot-check reveals a cosmetic gap
  that cannot cause an analyze/test failure.
- Grade A only when ALL commands pass AND the spot-check is clean.
- Analyzer **warnings/infos** (not errors) are a `regression-risk` / lint concern,
  not a gating failure here — `dart analyze` exits non-zero on errors; treat the
  exit code as the gate.
- Out of scope: spec adherence, test coverage quality, prior-art reuse — those are
  the parallel grading members' job. Grade only: did the Validation Plan pass?
