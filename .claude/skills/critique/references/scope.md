---
name: scope
version: 2
---

## Summary

Scope measures the bead's bounds and cohesion. Step count is a useful proxy but not the gate — three steps in three packages can fail scope, while ten steps that all touch the same actors/grammar block can pass. The rubric grades two questions together: *is this one concern* and *can this land as one commit (or one tightly coupled commit series)*. Scope matters because "spec too big" has two opposite responses — **trim** (same scope, less detail) and **split** (less scope, same detail-density). Grading scope independently lets the committee say "decompose, don't rewrite" — which is the only sane response when a bead is structurally too large.

An F on scope is not a failure of the spec writer's craft. It's a signal that the bead is the wrong unit of work. The right response to F is `bd dep add` and decomposition into children, not a rework of the original. The right response to A on scope is `fs ready`.

## Grades

### A

Small, single-concern, ~3-6 implementation steps. One commit makes sense (or a tight series where each commit is mechanical). The bead title can be read as one verb on one noun.

**No sibling-bead overlap.** If the bead has a parent epic, list its other children via `bd dep list <parent-id> -t parent-child` and check each sibling's `## Touches` section. Every file this bead modifies must either (a) not appear in any sibling's `## Touches`, or (b) appear with an explicit "out of scope (touched by sibling <id>)" disclaimer in one of the two. Two beads that both edit `internal/route/route.go` without coordination is the failure mode this clause prevents. Verify, do not assume.

### B

Cohesive, ~6-10 steps. Clear single feature, possibly with adjacent test and docs work. A reader can hold the whole change in their head.

### C

Borderline. Could split, but the scope is still narrative-coherent — there's one story being told, even if it spans two files or two minor sub-features. Often a sign that an A and a small B got bundled.

### D

Two clearly separate concerns crammed together. Should be two beads. Reading the spec, you can put your finger on the seam where one ends and the other begins.

### F

Epic disguised as a bead. Three or more concerns OR 15+ steps OR phases ("first do X, then Y, then Z"). The spec MUST decompose into children. Do not rebuild as-is; do not rewrite to be terser. Decompose.

## Examples

### Example: factoryskills-9vl — prune deprecated 0.3 names (A)

Single concern: remove three skill names and three agent filenames before reinstall. Six implementation steps (deprecation tables, helper, two wirings, two tests). Every step is on the same package (`internal/project/`). The bead reads as one verb on one noun: *prune deprecated names*. Grade: A.

### Example: factoryskills-d2u — two content bugs in actors/grammar block (A)

Two bugs but one block of text: the `actorsSection` constant in `prime_sections.go`. Both fixes are about canonical taxonomy in the same rendered table. Five steps total (two content edits, one positive-test update, one negative-test addition, one sanity check). The "two bugs" framing might suggest D ("two clearly separate concerns") — but they aren't separate. They share the file, the section, the rationale (post-ieh canonical names), and the test. Grade: A — narrow and cohesive.

### Example: factoryskills-cm3 — `fs init --dev` bin swap (B)

Slightly broader: introduces `internal/project/devmode.go` with detection helpers, adds `SwapBinToDev` and `RestoreBrewLinks` with sentinel errors, wires `--dev` and `--no-dev` through the init command, updates the help body. Roughly 8-10 steps spanning detection, mutation, restoration, and CLI surface. It could conceivably split (detection helpers as their own bead, then mutation, then CLI wiring), but the feature only makes sense as a unit — `--dev` without bin-swap is the bug, and `--no-dev` without `--dev` is half a feature. One feature, multiple files, narrative-coherent. Grade: B.

### Example: factoryskills-ieh — taxonomy audit (F, correctly handled)

ieh is the canonical F-correctly-handled. The ADR redefines skills, agents, lifecycle states, verdict outcomes, BLOCKED categories, comment grammar, actor names, and CLI verbs — eight separate axes. As implementation work, that's an epic; as a *decision* bead, it's bounded (one ADR, one design field). The right response was not to rebuild ieh as a smaller bead. The right response was: write the ADR, then file follow-on rename beads (5wx, jy0, the cascade), each of which is A or B on this rubric. Grade: F as written for implementation purposes, but correctly handled by being a `type=decision` bead whose only artifact is the ADR. F means decompose; ieh decomposed into the rename cascade.

### Example: factoryskills-oqu — Committee epic (F, correctly handled)

oqu introduces two new skills (`deliberate`, `marshal`-shaped chair and worker), three rubric reference files, a JSON Schema, a rubric-set declaration, two new agent definitions, an `internal/route/` package, two new `fs` subcommands (`deliberate`, `route`), and a routing policy. Easily 25+ implementation steps across at least four packages. As a single bead it would be impossible to review and impossible to land in one commit series. oqu is correctly typed as `epic` and decomposed into five children (foundations, rubric content [this bead], skill bodies, routing policy, integration). Grade: F as a unit; correct handling: decomposed. The decomposition is the answer — F means split, not fail.

## Calibration

- **Before grading A or B on a child of an epic, run `bd dep list <parent> -t parent-child`, then `bd show <sibling> --json` for each, and grep each sibling's `design` field for the file paths this bead touches.** A collision without a disclaimer in one of the two specs is the seam — drop scope to C or D. If the bead has no parent epic, also run `bd search` over the touched paths to catch unrelated open beads that already claim them.
- If between A and B, err toward A when the steps are independent enough to commit one at a time and each commit could revert cleanly. A-grade beads have step independence as a property, not just a count.
- If between B and C, err toward B when every step touches the same package or the same exported symbol. Cohesion outweighs step count up through ~10 steps.
- If between C and D, err toward D when two steps target different packages with no shared symbol, no shared test, and no shared rationale. The seam is where the cohesion ends.
- If between D and F, err toward F when the bead description already mentions phases ("first do X, then Y") or numbered milestones. Phases are the giveaway that this is an epic — phases are children waiting to happen.
- A bead spanning many files but a single concept (like d2u's two-bugs-one-block, or 9vl's six-callsites-one-pattern) is A, not C. Count concepts, not files.
- A bead with one file but two concepts (a refactor *and* a new feature in the same file, both unrelated) is C or D, not A. Count concepts, not files.
- Type=decision beads grade scope by the breadth of the decision, not by counting implementation steps (there are none). A decision bead that ranges across 8 axes (like ieh) is F at the implementation level but is the right unit for the decision itself — the F triggers decomposition into rename children, not rewrite.
- When in doubt at the F boundary, count distinct verbs in the title. "Add X and refactor Y and document Z" is three verbs and almost always F. "Fix the prune logic" is one verb and rarely worse than B.
- **On a re-deliberation round** (the bead carries a prior `inspector: REBUILD.`, `inspector: RESPEC.`, or `inspector: DECOMPOSE.` verdict comment — see the re-deliberation step in `agents/critique.md`), the implementation revealed where the bead's seams actually fell. Read the branch diff and the verdict. Downgrade if the diff shows (a) the bead crossed a seam that wasn't visible at spec time — two clearly separable concerns that the build had to commit together, (b) the spec named one file but the implementation had to touch a sibling package the spec did not mention (missed cross-file dependency), or (c) the inspector's `DECOMPOSE` finding cites a split that the as-written bead structurally forces. A spec that graded A on cohesion-on-paper but whose diff sprawls across two packages with no shared symbol is no longer A on this round. Drop one grade band per seam revealed, capped at F. If the diff is tight and single-concern and the verdict is `REBUILD` for non-scope reasons, the grade is unchanged.
