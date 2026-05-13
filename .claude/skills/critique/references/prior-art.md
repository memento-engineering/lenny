---
name: prior-art
version: 1
---

## Summary

Prior-art measures whether the spec respects code that already exists in the
repository. Every step that adds a function, type, or subsystem should answer
the question: *does something equivalent already live in this codebase?* A
spec that names an existing package and explains how the new work extends it
scores high. A spec that builds a parallel subsystem next to one that already
does the job scores low — even if the parallel implementation is, in
isolation, clean code.

This rubric is about *the codebase as constraint*, not about taste. It does
not grade idiomatic-Go style, naming conventions, or whether the spec uses
the "right" stdlib feature. Those taste-level concerns belong in future
extensions (e.g. `style@v1`), not here. Prior-art asks one question:
*did you check what's already there?*

The grader is expected to verify this rubric's claims against the world —
use Grep/Glob/Read on the repo to confirm that named existing packages,
files, and symbols resolve, and use `bd show <id>` / `bd search` on the
backlog to confirm closed beads cited as prior art actually exist and cover
the surface the spec claims.

## Grades

### A

The spec explicitly cites the existing code it extends (by package path,
file, or symbol) and disclaims duplication where a naive reader might suspect
it. New functions are named alongside the existing functions they sit next
to. Where the spec deliberately does NOT touch an obvious-adjacent file, it
says so and gives the reason.

### B

The spec names the existing subsystem it extends in prose, but a step or two
adds adjacent helpers without saying whether a similar helper already exists
elsewhere. The omission reads as economy (the helper is genuinely new) rather
than as blindness to the codebase.

### C

The spec adds at least one symbol that a quick grep would have shown is
already provided by an existing package, but the duplication is small and
self-contained — a private helper, a single utility function — not a
parallel subsystem. The fix is renaming the new symbol to the existing one,
not a redesign.

### D

The spec proposes a parallel subsystem at a non-trivial scale (a new package,
a new pipeline, a new lifecycle layer) without cross-referencing the
existing one. Two equivalent code paths would land if the spec executed
as written. The fix is a redesign that routes through the existing
subsystem; the spec is salvageable but not as written.

### F

The spec reinvents an existing subsystem from scratch. For example, the
plan proposes a new status-validation helper at `internal/statuscheck/`
when `internal/lifecycle/ValidateTransition` already does exactly that job
and is already wired through every command. The spec author did not look,
or looked and chose not to acknowledge. F here is a respec signal — the
work itself is fixable inside the bead by rewriting the steps to extend
rather than parallel-build.

## Examples

### Example: factoryskills-eed — verify-against-the-world critique upgrade (A)

eed's design field opens by carving scope from the parent epic, then names
the existing file (`internal/commands/critique.go:39`) whose dispatch prompt
template "is already compatible with the narrowed rule." The spec ships a
deliberate non-change to that Go file with the reasoning quoted:

> Leaving the Go template alone is a deliberate scope choice — touching it
> would mean editing tests in `internal/commands/critique_test.go` and risk
> failing CI for a non-load-bearing wording change.

This is textbook A. The author looked at the existing code path, decided it
already does the job, and documented that decision. The graders should be
able to confirm by running `grep -n "do not load siblings"
internal/commands/critique.go` and seeing the live template line. Grade: A.

### Example: factoryskills-9vl — prune deprecated skill/agent names on reinstall (A)

9vl's Implementation Plan extends the existing install loop in
`internal/project/project.go` — adding `deprecatedSkills` and
`deprecatedAgents` `var` blocks "near the existing `SkillDir`/`AgentDir`
constants" — rather than introducing a parallel cleanup subsystem. The spec
names the existing `InstallSkills` / `InstallAgents` functions as the code
it threads the prune step into, and explicitly bounds the new behavior
("Only names we know we shipped — never user content") so the new code path
sits inside the existing one instead of beside it. Graders can confirm by
opening `internal/project/project.go` and seeing the `deprecatedSkills`
var co-located with the install constants. Grade: A.

### Example: synthesized anti-pattern — parallel status-validation helper (F)

Compare a hypothetical F-grade snippet:

```
1. Add a new package `internal/statuscheck/` with a `Check(from, to string)
   error` function that returns an error if the transition is not allowed.
2. Define the allowed transitions inline in `statuscheck/transitions.go`.
3. Call `statuscheck.Check` from `internal/commands/done.go` before updating
   the bead.
```

This spec ignores `internal/lifecycle/ValidateTransition`, which already
takes `(from, to lifecycle.Status) error`, already encodes the transition
map, and is already called from every transition site. A grep for
`ValidateTransition` would have shown 6+ callers. The right plan extends
`internal/lifecycle/` (or routes through it); the wrong plan builds the
second one. Grade: F.

Note: this F example is a deliberately synthesized anti-pattern rather than
a citation of a real closed bead. The prior-art rubric is new at @v1 and the
project's calibration corpus is small — closed beads went through committee
gating that caught reinvention pathologies before they shipped, so no real
F-grade exhibit exists in history. Graders should treat the synthesized
shape as authoritative for the band and substitute a real bead id here as
the corpus grows.

## Calibration

- If between A and B, err toward A when the spec names existing code by
  exact path AND explains the relationship ("extends", "wraps", "leaves
  alone because X"). A spec that names the file without naming the
  relationship is B.
- If between B and C, err toward C when a grep of any new symbol the spec
  introduces returns an existing definition. Even a small overlap with an
  existing utility is a C — the spec didn't look.
- If between C and D, err toward D when the parallel surface is a new
  package or a new pipeline (not just a helper). Package boundaries
  matter — a duplicated helper inside an existing package is C; a
  duplicated *package* is D.
- If between D and F, err toward F when the spec contains language like
  "build a system that...", "introduce a new mechanism for..." referring
  to a behavior the codebase already provides. That phrasing is the
  giveaway that the author was working from a blank page.
- A deliberate parallel implementation — e.g. a second router for a
  different purpose — is NOT a prior-art failure if the spec explicitly
  contrasts the two and names why one isn't reused. The discriminator is
  whether the author acknowledged the existing code. Acknowledged-and-
  rejected is A; ignored is F.
- Out of scope: taste-level judgments. Even if a spec uses non-idiomatic
  Go, an unusual error-wrapping convention, or an off-style naming choice,
  that is not a prior-art concern. Grade only against codebase
  duplication. Idiomatic-style concerns are for future extension rubrics.
