---
name: scope-creep
version: 1
---

## Summary

Scope-creep measures whether the diff stayed inside the surface the spec
named. The bead's `## Touches` section enumerates the files the bead is
allowed to change and the symbols it adds; the Implementation Plan bounds
the behavior. A diff that edits files outside that surface, or changes
behavior the plan didn't call for, is creeping — even if the extra change
is, in isolation, an improvement.

**What to read.** The diff: `git diff $(git merge-base main <branch>)..<branch>`
(use `--stat` first for the file list). The spec: the bead's `## Touches`
("Files:" and "Symbols added/exposed:") and `## Implementation Plan`.

## Grades

### A
Zero files modified outside the spec's named surface. Every symbol the
diff adds is listed under `## Touches`. No behavior change beyond what the
Implementation Plan describes. The diff is exactly the bead.

### B
The diff touches only named files, but adds a small unlisted symbol (a
private helper) or a trivial drive-by (a typo fix, an import sort) that
any reviewer would wave through. The spillover is cosmetic, not
behavioral.

### C
One file outside the named surface is modified, but the change there is
small and plausibly necessary (a caller updated to match a new
signature). The spec should have named it; the diff is salvageable as-is
with a `## Touches` amendment.

### D
Several unlisted files are modified, or a meaningful behavior change lands
that the Implementation Plan never mentioned. The bead did more than it
said it would; a reviewer can't tell what was intended.

### F
Spillover into unrelated files or subsystems, or behavior change well
beyond the Implementation Plan — the diff bundles a second, unspecified
change. Ambiguous disposition (was the spec's scope wrong, or did the
build go off-piste?), so this routes to a human, not auto-rebuild.

## Calibration
- If between A and B, err toward B when the diff adds any symbol not
  listed under `## Touches`, even a private one — A means the surface
  matches exactly.
- If between B and C, err toward C when a file outside the named "Files:"
  list is modified at all, however small.
- If between C and D, err toward D when more than one unlisted file is
  touched, or the out-of-surface change alters behavior.
- If between D and F, err toward F when the diff contains a coherent
  second change (a refactor, a feature) that the spec never mentioned —
  that's a bundled commit, not creep at the margin.
- Out of scope: whether the in-scope changes correctly implement the plan
  (`spec-adherence`) or whether they break anything (`regression-risk`).
  Grade only the *boundary* — did the diff stay where the spec said.
