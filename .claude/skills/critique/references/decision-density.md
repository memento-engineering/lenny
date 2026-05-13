---
name: decision-density
version: 2
---

## Summary

Decision density measures judgment calls per step. It is distinct from concreteness: a spec can be perfectly literal — "edit `foo.go`, add function `Bar`" — and still leave the builder choosing between three valid designs. Concreteness asks *did the spec say where and what*; decision density asks *did the spec say how to choose*. The cost of high decision density is mode-dependent. A cheap-tier builder drifts on judgment, picking a plausible-but-wrong design. An expensive-tier builder wastes cycles re-deciding what discover should have settled, and the resulting code reflects the builder's taste rather than the project's. Either way, the spec wasn't doing its job.

A judgment call is any step where the builder must compare alternatives and pick one. "Add error handling here" is a judgment call (which errors? wrap or sentinel? exit or log?). "Return `fmt.Errorf("readlink %s: %w", brewBinPath, err)`" is not. The cleanest A-grade specs decide everything in advance and leave the builder to type.

## Grades

### A

Zero judgment calls. Every step is mechanical: do X, run Y, expect Z. Where multiple designs were possible, the spec picked one and named it. The builder commits without ever asking "wait, which way does this want to go?"

**ADR lookup is not a judgment call.** If a spec implies or cites a recorded decision ("per the lifecycle ADR", "as ADR-0007 specifies", or even a load-bearing convention like actor naming or commit grammar), the grader must verify the ADR exists before awarding A. Run `ls docs/adrs/` or `bd search type:decision` and confirm the cited decision is recorded. A spec that hand-waves "the lifecycle ADR covers this" without the ADR actually existing is leaving a decision unmade — that's not A.

### B

One or two judgment calls, well-scoped, with stated reasoning. The spec acknowledges the choice ("could be a generic helper or inlined; we inline because there's only one caller") and the builder doesn't have to weigh tradeoffs from scratch.

### C

Several scattered judgment calls; some have reasoning, some don't. The spec passes through choices implicitly — naming a function but not its signature, naming a flag but not its default, naming a test but not what it asserts.

### D

Every other step needs the builder to make a non-trivial design choice. The plan looks like a checklist but each item expands into a small decision tree. Two competent builders following the same plan would produce noticeably different code.

### F

The spec is a sketch; the builder is co-designing. Phrases like "design the schema for X", "figure out how Y should fit", "decide which Z to keep" anchor F. The spec hasn't made the decisions yet — it just enumerates the surface area.

## Examples

### Example: factoryskills-9vl — prune deprecated 0.3 names (A)

This is a model A. Every step names exactly what to delete and exactly what to write:

```
var deprecatedSkills = []string{
    "build",
    "review",
    "supervise",
}

var deprecatedAgents = []string{
    "build-worker.md",
    "specify-worker.md",
    "review-worker.md",
}
```

A `pruneDeprecated` helper is fully written out (signature, logging label, error wrapping, missing-entry no-op). The wiring step names the exact insertion point ("immediately after `os.MkdirAll(destDir, ...)` and before the `os.ReadDir(srcDir)` loop") and explains the order ("the destination must exist before we try to stat children, and pruning must happen before install so a renamed skill replacing a deprecated name still works cleanly"). There are no decisions left. Three deprecated strings, one helper, two callsites — type it. Grade: A.

### Example: factoryskills-d2u — two content bugs in actors/grammar block (B)

d2u is a clean B. The plan is mechanical (replace one string-literal line, rename `supervise` to `marshal`, update one test slice, add a forbidden-token assertion). The literal before-and-after is quoted in the plan. There is one minor judgment call — the column-alignment note: "Preserve the table's column alignment by keeping the same total width before the parenthesis (replace `supervise` with `marshal  ` — note trailing spaces — so the comment column does not shift)". The builder has to count characters once. That's the only real judgment in the bead, and the spec stated the reasoning. Grade: B is fine, not a defect — B is what most well-written small bugfixes look like.

### Example: factoryskills-ieh — taxonomy audit (D/F)

ieh is a *decision* bead, not an *implementation* bead, and it grades F on this rubric for that reason. Its description asks the writer to "Audit names already in the system... and decide on a unified taxonomy". The body is the ADR — the output of judgment, not a plan to follow. A representative early-discovery framing reads:

> "decide which lifecycle names to keep" — collapse `pending_review` and proposed `spec_pending_review` into something parallel; pick the verdict vocabulary; pick whether `BLOCKED` and `respec` overlap.

That is co-design, not implementation. The builder isn't typing; the builder is choosing what the system should be. F is the right grade — and the right response to F here is *not* to rewrite as A. It's to recognize the bead as a decision, write the ADR, and let downstream rename beads (each A or B on this rubric) execute the decision. Grade: F, correctly handled.

### Example: factoryskills-oqu — Committee epic (D)

The Committee design field names file paths (`skills/deliberate/SKILL.md`, `skills/critique/references/concreteness.md`), names the routing policy in pseudo-Go, and names the labels that get written. But the per-rubric content, the JSON Schema fields, and the routing thresholds are still pending decisions ("Bumping the A-grade definition for `concreteness` bumps `concreteness@v2`" — but what does the A-grade definition say?). For the *epic* this is the right altitude, and oqu is correctly decomposed into children. But on the decision-density rubric the epic itself grades D — every named artifact still expands into design work. Children like d5i (this bead) are the A/B-grade implementation work. Grade: D for the epic, which is the right way for an epic to score.

## Calibration

- **Before grading A or B, enumerate every ADR or recorded decision the spec cites or implies, and confirm each one exists.** Run `ls docs/adrs/` (filenames are `NNNN-<slug>.md`) and `bd search type:decision status:recorded` (or `bd list --type decision --status recorded`). If a cited ADR is missing, the spec has a decision it pretends is settled — drop to C or below. This is lookup, not judgment.
- If between A and B, err toward A when the "judgment call" is actually a documented project convention (CLAUDE.md naming rules, conventional commits, bd actor identities). Following a written convention is not a decision — it's lookup.
- If between B and C, err toward C when judgment calls lack stated reasoning. A B-grade bead says "we inline because there's only one caller"; a C-grade bead says "inline this" and leaves the alternatives unmentioned.
- If between C and D, err toward D when the same kind of choice ("which test framework", "which error wrapping", "which file to extend") recurs across multiple steps without a single resolution. Repeated similar judgment calls compound.
- If between D and F, err toward F when the spec contains the phrase "design <X>", "figure out <Y>", or "decide between <A> and <B>". Those phrases name unresolved decisions outright.
- A bead with explicit "Out of scope" sections often grades higher on this rubric than its length suggests, because it has named decisions made, even if the made decision was "not now". An A-grade bead does not make the builder discover the boundary.
- Concreteness and decision density usually correlate but not always. cm3 is A on both. ieh is A on concreteness within the ADR (every renamed name is literal) and F on decision density (because the bead's job *was* to make the decisions). Grade each axis independently.
- Decision-bead specs (type=decision) are an exception class. Grading them on decision density measures whether the *decision was made*, not whether the *implementation is mechanical* — because there is no implementation. If the ADR is complete and unambiguous, that is the A; if the ADR ends with open questions, that is D or F.
