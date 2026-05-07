name: decision-discovery
description: Use when exploring architectural decisions — ADR exploration with context, options, tradeoffs, and consequence documentation

# Decision — Discovery

Decisions (ADRs) document architectural choices with context, options, and rationale.
Discovery is structured around exploring tradeoffs, not building features.

## Phase 1 — Discovery

**First:** Follow [../brainstorming.md](../brainstorming.md) for the standard discovery process,
with the following adjustments.

### Decision-Specific Discovery

Instead of "propose 2-3 approaches and pick one," decisions require explicit
documentation of all options:

1. **Context** — What forces are driving this decision? What constraints exist?
2. **Options** — Enumerate all viable options (minimum 2). No "we should just do X."
3. **Tradeoffs** — For each option: what do you gain? What do you lose?
4. **Recommendation** — Lead with your recommendation and explain why.
5. **Consequences** — What changes downstream if we go with the recommendation?

### Differences from Feature Discovery

- **Output is an ADR, not a design.** The bead's description should be structured
  as an ADR (Context, Decision, Consequences).
- **All options must be documented** — even rejected ones. Future readers need to
  understand *why* alternatives were rejected.
- **No Phase 1b.** Decisions don't decompose into stories. They inform other work.

### Exit Criteria

Decision discovery is complete when:
- All options are documented with tradeoffs
- Human has made the decision (explicitly, not assumed)
- Consequences are understood
- ADR is written to the bead description

When done: "Decision recorded."
Decisions typically don't need the specify skill — the ADR itself is the artifact.
If the decision creates follow-up work, create separate task/feature beads and link
them: `bd dep add <task-id> <decision-id>`.

### ADR Persistence

The decision bead's description IS the ADR. After approval, persist it to the
project's ADR directory (e.g., `docs/adrs/`) as a markdown file. The ADR file
should reference the decision bead ID for traceability.
