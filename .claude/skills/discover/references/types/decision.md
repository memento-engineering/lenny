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

When done: hand off with `fs record <id>`. The verb persists the bead's
description to `docs/adrs/NNNN-<slug>.md` and transitions `draft → recorded`.

Decisions do not pass through specify/forge/inspect — `fs record` is the
terminal verb. The 8 non-applicable fs verbs (`specify`, `convene`,
`ready`, `forge`, `done`, `verdict`, `route`, `merge`) reject decision
beads with a message pointing at `fs record`.

If the decision creates follow-up work, create separate task/feature beads
and link them: `bd dep add <task-id> <decision-id>`.

### ADR Persistence

`fs record <id>` writes the bead's description to
`docs/adrs/NNNN-<slug>.md` (auto-numbered, slugified from the title).
Override the slug with `--name <slug>`. Use `--no-file` when the ADR
file already exists (e.g., migrating an existing decision bead). The bead
description remains the source of truth — re-recording is not supported
(the bead is then in `recorded`); update the description and the file
side-by-side if the ADR needs revisions.
