---
name: coherence
version: 1
---

## Summary

Coherence measures whether the spec fits the bead graph it lives in. A bead
is rarely alone: it has a parent epic, sibling beads, and sometimes
children. The spec should reference those relationships explicitly —
carving scope from siblings, citing the parent's design field, naming
children where they exist. A spec that ignores its neighbors duplicates
work, contradicts decisions already made elsewhere in the epic, or carves
a scope that overlaps another open bead.

The cost of poor coherence is silent collision: two beads ship the same
file with different content, two siblings declare overlapping `## Touches`
sections, or a child contradicts a decision its parent epic already
recorded. The committee can only catch this if the spec made the
relationships visible.

The grader is expected to verify this rubric's claims against the backlog
— use `bd show <parent-id>`, `bd show <sibling-id>`, `bd dep list`, and
`bd search` to confirm that the relationships the spec claims actually
match what the database says. If the spec names a sibling that no longer
exists or names a parent it isn't actually a child of, that is a verification
finding, not a phrasing critique.

## Grades

### A

The spec explicitly carves scope from sibling beads (named by id, each
with an "out of scope here" line), cites the parent epic by id and quotes
or paraphrases the relevant excerpt from its design field, and references
children if any exist. A reader can tell from the spec alone where this
bead's surface ends and the neighbors' begin.

### B

The spec cites the parent and at least one sibling, but one or two
neighbors are unmentioned. The omissions are small (a sibling whose
surface obviously doesn't overlap) rather than load-bearing.

### C

The spec mentions the parent in passing but does not engage with the
parent's design field, or mentions siblings without carving scope from
them. The graph is acknowledged but not used to constrain the spec.

### D

The spec proceeds as if the bead were standalone. The parent is not
named even when one exists. Sibling overlap is not addressed even when a
quick `bd dep list <parent>` would have shown two beads claiming the same
file.

### F

The spec duplicates a closed sibling (proposes work that another bead in
the same epic has already shipped), or contradicts the parent epic's
design field on a load-bearing point (e.g. proposes a Go change in a
child that the parent epic explicitly carved out to a different child).
F is a decompose/relocate signal: the spec belongs somewhere else in the
graph, not in this bead.

## Examples

### Example: factoryskills-eed — verify-against-the-world critique upgrade (A)

eed's design opens with "Scope boundary vs. siblings" and names every
sibling individually (`26o`, `516`, `m2w`, `v3a`), each with an explicit
"out of scope here" line. The parent epic (`factoryskills-tsk`) is cited
by id and the relevant excerpt of its design field is quoted as a
blockquote:

> All critique agents gain explicit permission and an explicit
> *expectation* to read the codebase and backlog while grading...

The spec is unambiguous about where eed ends and where siblings begin.
Verifiable: `bd dep list factoryskills-tsk` should list `eed` along with
`26o`, `516`, `m2w`, `v3a` as children. Grade: A.

### Example: factoryskills-9ef — undeclared cross-bead deps (F-via-history)

9ef is the closed retrospective bead that documented the failure mode
where sibling beads in the butane_flutter Android epic (`q4y`, `ehk`,
`iyy`) declared deps only on the foundation bead `ngt`, but their specs
referenced fields and helpers that one of the siblings added. The
original specs (pre-9ef-investigation) are the F exhibits: each spec
named symbols the bead's own diff would not produce, without declaring
the inter-sibling dependency. 9ef itself names the symptom: "parallel-
built branches fail to merge with confusing diffs." The fix is the
sibling cross-check now baked into `skills/specify/references/process.md`.
Grade: F for the original specs (lesson absorbed via 9ef's recording).

## Calibration

- If between A and B, err toward A when the spec names AT LEAST every
  sibling whose surface plausibly overlaps. Naming an obviously-
  unrelated sibling adds noise; naming the ones that could collide is
  the signal.
- If between B and C, err toward C when the parent epic's design field
  contains a decomposition list and the spec does not reference the
  child slot it occupies. Citing the parent without engaging with the
  parent's decomposition is a half-citation.
- If between C and D, err toward D when `bd dep list <parent>` returns
  open or in_spec siblings whose titles overlap this bead's title, and
  the spec does not address them. Open-sibling overlap is the bright
  line for D.
- If between D and F, err toward F when a closed sibling (status =
  closed) covered the surface this spec proposes. Closed-sibling
  duplication is the highest-cost coherence failure: the work has
  already shipped.
- A bead with no parent and no siblings (a standalone bug fix, a top-
  level epic with no peers) is graded only on what's there to grade.
  If there's no graph, the spec can't engage with it. Don't penalize a
  truly orphan bead for not citing nonexistent neighbors.
- A closed sibling that is no longer load-bearing (superseded by a
  later closed bead, or rolled back) is not a coherence failure to
  ignore. The grader should verify with `bd show <sibling-id>` whether
  the sibling's outcome is still in effect.
