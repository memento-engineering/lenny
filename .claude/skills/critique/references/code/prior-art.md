---
name: prior-art
version: 1
---

## Summary

Prior-art (code phase) measures whether the diff extends what already
exists in the repo instead of building a parallel version of it. Every
new function, type, or subsystem in the diff should answer: *does
something equivalent already live here?* A diff that threads a new step
into an existing loop, reuses an existing helper, and cites the prior art
in its commit body scores high. A diff that lands a second subsystem next
to one that already does the job scores low — even if the new code is
clean in isolation.

This is the code-phase counterpart of the spec-side `prior-art` rubric:
that one graded whether the *plan* acknowledged existing code; this one
grades whether the *diff* actually reused it. Same question, different
artifact.

**What to read.** The diff: `git diff $(git merge-base main <branch>)..<branch>`.
The repo, via Grep/Glob/Read — for each new symbol the diff introduces,
check whether an equivalent already exists. The commit body (`git log
$(git merge-base main <branch>)..<branch>`) for prior-art citations.

## Grades

### A
The diff extends existing helpers/patterns — new code sits inside an
existing function/package rather than beside it. Where a naive reader
might suspect duplication, the commit body or a code comment cites the
prior art it builds on. No symbol in the diff duplicates one a grep would
have found.

### B
The diff reuses the main existing subsystem, but adds an adjacent helper
without noting whether a similar one already exists elsewhere. Reads as
economy (the helper is genuinely new), not blindness.

### C
The diff adds at least one symbol a quick grep shows already exists, but
the duplication is small and self-contained — a private helper, one
utility function — not a parallel subsystem. The fix is renaming to the
existing symbol, not a redesign.

### D
The diff lands a parallel subsystem at non-trivial scale (a new package,
a new pipeline) without routing through the existing one. Two equivalent
code paths now exist. Salvageable, but the fix is a redesign that reuses
the existing subsystem.

### F
The diff reinvents an existing subsystem from scratch — e.g. a new
status-validation helper when `internal/lifecycle/ValidateTransition`
already does that job and is wired through every command. This is a
rebuild signal.

## Calibration
- If between A and B, err toward A only when the diff both reuses
  existing code AND the commit body/comment names what it builds on;
  reuse without acknowledgement is B.
- If between B and C, err toward C when a grep of any symbol the diff
  adds returns an existing definition — even a small overlap means the
  author didn't look.
- If between C and D, err toward D when the parallel surface is a new
  *package* or pipeline, not just a helper inside an existing package.
- If between D and F, err toward F when the diff's commit messages or
  comments use language like "new mechanism for…" / "build a system
  that…" describing behavior the repo already provides.
- A deliberate parallel implementation (e.g. a second router for a
  different purpose) is NOT a failure if a commit-body note contrasts the
  two and says why one isn't reused. Acknowledged-and-rejected is A;
  ignored is F.
- Out of scope: taste-level Go style, naming conventions, stdlib choices.
  Grade only codebase duplication.
