---
name: decisions
version: 1
---

## Summary

Decisions measures whether the spec respects the project's recorded
architectural decisions. The factory has two homes for binding decisions:
ADRs in `docs/adrs/` and decision-type beads with `status=recorded` (per
ADR 0003, `docs/adrs/0003-decision-bead-lifecycle.md`). Every spec that
touches a surface those decisions cover should cite the relevant
decision(s) and either implement them, extend them, or — rarely —
explicitly propose overriding them. A spec that silently contradicts a
recorded decision is the most expensive coherence failure: it undoes work
the project has already deliberated, often without anyone noticing until
the contradiction ships.

This rubric is distinct from coherence (which grades the bead-graph fit)
and from prior-art (which grades codebase duplication). Decisions asks:
*did the spec author check the ADRs and the recorded decision beads, and
align with what they say?*

The grader is expected to verify this rubric's claims against the world.
Run `ls docs/adrs/` to enumerate ADRs; run `bd list --json` filtered for
`status=recorded` and `issue_type=decision` to enumerate live decision
beads; `bd show <decision-bead-id>` for the rationale. A claim that "no
recorded decision applies" is verifiable; an unstated contradiction is
the F.

## Grades

### A

The spec explicitly cites the load-bearing ADR(s) it implements, by file
path (`docs/adrs/000N-...md`) and/or by the recording bead's id
(`factoryskills-XYZ`). Where the spec extends or refines a recorded
decision, that extension is named. Where no recorded decision applies,
the spec says so explicitly ("no ADR or recorded decision bead covers
this surface; this work is standalone").

### B

The spec cites the relevant ADR or decision bead, but the connection is
named without quoting the load-bearing line. A reader can tell which
decision is being implemented; a reader cannot tell which clause of the
decision constrains the work.

### C

The spec implements work that is clearly downstream of a recorded
decision (e.g. extends a subsystem the decision established) but does
not cite the decision at all. The alignment is accidental rather than
acknowledged.

### D

The spec touches a surface a recorded decision covers and partially
contradicts it without acknowledgement. For example, the spec adds a
persisted projection of bead state when ADR 0001 (declarative lifecycle)
rules that derived projections are not persisted — but the contradiction
is small, easily reversed, and may have been an oversight.

### F

The spec contradicts a load-bearing recorded decision (status=recorded,
type=decision) without acknowledging it. The contradiction is structural,
not incidental: implementing the spec as written would undo or invert the
decision. F is a human-ultimatum signal — the spec author should be
asked whether they intend to override the decision (in which case a new
ADR is owed) or whether they will rework the spec to align.

## Examples

### Example: factoryskills-78c — decision-bead lifecycle (A)

78c closed as `Decision-bead lifecycle: recorded status + fs record verb +
reject sweep`. Its very purpose is to implement ADR 0003
(`docs/adrs/0003-decision-bead-lifecycle.md`, recorded as
`factoryskills-60g`). The ADR is named in the bead's chain of work, the
recording bead is linked, and the implementation paths
(`internal/lifecycle/`, `internal/commands/record.go`) extend the
subsystem ADR 0001 established. A grader running `bd show factoryskills-
60g` sees the recorded decision; running `ls docs/adrs/` sees the ADR
file; running `bd dep list factoryskills-78c` sees the link to 60g.
Three independent verifications agree. Grade: A.

### Example: synthesized anti-pattern — persisted grade projection (F)

Compare a hypothetical spec that proposes:

```
1. Add `.factoryskills/grades.json` written by `fs deliberate`, storing
   each bead's last grade-set keyed by bead id.
2. Read `.factoryskills/grades.json` from `fs route` to avoid
   re-deliberating.
```

This contradicts ADR 0001 (factoryskills-goz, `docs/adrs/0001-declarative-
bead-lifecycle.md`), whose load-bearing rule is "status is status,
derived projections are not persisted." Grades are labels on the bead;
the source of truth is `bd`, not a JSON cache. The spec does not name
the ADR, does not mention factoryskills-goz, and proposes the exact
pattern the ADR rules out. Grade: F. The right response is a human
ultimatum: either rework the spec to read grades from bd labels at
deliberation time (aligning with the ADR), or write a new ADR proposing
the projection cache and superseding goz.

## Calibration

- If between A and B, err toward A when the spec cites the ADR by file
  path AND the recording bead by id AND quotes the load-bearing clause.
  Citing one of the three (file path alone) is B; citing all three is A.
- If between B and C, err toward C when the spec implements work
  downstream of an ADR but the ADR is never mentioned. Implicit
  alignment is not citation — the grader's job is to verify, and the
  spec should make verification trivial.
- If between C and D, err toward D when the spec adds a small piece of
  behavior the ADR rules out (a persisted cache, a parallel state field,
  a duplicate status name) but the net effect is reversible and the rest
  of the spec aligns. D means "respec, not redesign."
- If between D and F, err toward F when the contradiction is structural
  — i.e. implementing the spec means the ADR no longer holds for the
  surface in question. Structural contradictions earn the human-
  ultimatum routing.
- A decision bead with `status=draft` (not `recorded`) has no binding
  force on this rubric. Only `status=recorded` decision beads count.
  Verify with `bd show <id>` before treating a citation as load-bearing.
- An ADR explicitly marked `Superseded` (per ADR 0001's status field) is
  not load-bearing for this rubric. Grade only against ADRs whose status
  is `Accepted` and recording beads whose status is `recorded`.
- A spec that proposes a new ADR (i.e. names itself as a decision-type
  bead, follows ADR 0003's recording flow) is not graded on contradiction
  with the very decision it proposes to record. Decision beads are
  graded on internal coherence and on whether they cite prior ADRs they
  supersede or extend.
