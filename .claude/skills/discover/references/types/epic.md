name: epic-discovery
description: Use when discovering or decomposing epics — Phase 1 discovery plus Phase 1b refinement with story creation, dependency wiring, and approval

# Epic — Discovery & Refinement

Epics are large work items that span multiple independent concerns. They go through
both standard discovery AND a refinement phase before specification.

## Phase 1 — Discovery

**First:** Follow [../brainstorming.md](../brainstorming.md) for the standard discovery process.

### Epic-Specific Discovery Questions

In addition to the standard discovery questions, epics need:

- What are the major components or subsystems involved?
- Are there natural phases or milestones?
- What are the external dependencies or integration points?
- What's the risk profile — where are the unknowns?
- What's the minimum viable slice that delivers value?

### Identifying Epics

Work should be typed as `epic` when:

- Implementation would span 3+ independent concerns
- Multiple phases with different dependencies
- Work that would take multiple build sessions
- Plan would exceed 10 implementation steps
- Multiple design decisions need to be made independently

Flag early: "This looks like an epic." If uncertain during discovery, proceed with
the design — it can be promoted to epic during Phase 1b or by the specify skill
if the spec turns out too large.

### Exit

Same as standard discovery: design approved by human. Then proceed to Phase 1b.

---

## Phase 1b — Epic Refinement

After design approval, decompose the epic into properly scoped stories before
specification. This is still discovery work — understanding scope boundaries and
execution order — not specification.

### Process

```
1. READINESS   → Is the epic ready to decompose?
2. SEAMS       → Where are the natural boundaries?
3. STORIES     → Create properly scoped children
4. DEPS        → Wire the dependency graph
5. APPROVAL    → Human approves the decomposition
```

### Step 1 — Epic Readiness

Before decomposing, verify the epic has enough context:

- [ ] Design is approved (Phase 1 complete)
- [ ] Scope boundaries are clear (what's in, what's out)
- [ ] Success criteria exist at the epic level
- [ ] No open questions that would change the decomposition

If readiness fails, return to discovery. Don't decompose a half-understood epic.

### Step 2 — Identify Seams

Find the natural boundaries for decomposition. Look for:

- **Infrastructure vs Intelligence vs Integration** — build order layers
- **Independent concerns** — things that don't share state or interfaces
- **Phase gates** — where one piece must be done before the next can start
- **Vertical slices** — end-to-end functionality that delivers user value
- **Risk boundaries** — isolate unknowns from known work

Present the proposed seams to the human: "Here's how I'd split this. Each of these
would be its own story."

**Shared state check:** as you propose seams, ask: "Will any of these stories add fields, helpers, types, or files that another story will reference?" If yes, either restructure so each story is self-contained, OR plan to declare an explicit dependency in Step 4. Implicit shared state is a known failure mode (see factoryskills-9ef).

### Step 3 — Create Stories

For each identified seam, create the child bead:

```bash
fs discover "story title" --type feature
```

**Story scoping rules:**
- Each story should be independently implementable
- Each story should be independently testable
- Each story should deliver a verifiable artifact (not just "setup")
- Aim for 3-8 implementation steps per story (the specify skill will validate)
- If a story would need 10+ steps, it's probably an epic itself — recurse

**Naming:** Stories should describe *what they deliver*, not *what they touch*.
- "Message buffering & debounce"
- Not "Slack module changes"

### Step 4 — Wire Dependencies

Map the dependency graph between stories:

```bash
bd dep add <blocked-id> <blocker-id>
```

**Dependency rules:**
- Only add dependencies where the blocked story genuinely cannot start without
  the blocker being complete
- Prefer shallow graphs — deep chains slow down parallelism
- If everything depends on one story, that story might be too large
- Verify `bd ready` returns the expected starting stories

Present the dependency graph to the human: "Here's the build order. X and Y can
happen in parallel once Z is done."

### Step 5 — Approval

The human approves the decomposition:
- Epic scope and boundaries
- Story list and descriptions
- Dependency graph
- Proposed priorities

Confirm explicitly with the human: "No story references state added by another sibling without a declared dependency, correct?" The specify process cross-checks `## Touches` sections at spec time, but catching this during decomposition saves a round trip.

### Populating the Epic

After decomposition is approved, update the epic bead:

```bash
# High-level acceptance criteria for the whole epic
bd update <epic-id> --acceptance '- [ ] Epic-level criterion 1
- [ ] Epic-level criterion 2'

# Design field: decomposition overview (unlimited size for epics)
bd update <epic-id> --design '## Decomposition

### Stories
- <child-id>: <title> — <one-line scope>
- <child-id>: <title> — <one-line scope>

### Dependency Graph
<text representation>

### Build Order
1. <child-id> (unblocked, start here)
2. <child-id> + <child-id> (parallel after step 1)
3. ...'
```

### Priorities

Set priorities during decomposition, not after:

| Priority | When |
|----------|------|
| P1 | On the critical path — blocks other stories |
| P2 | Important but not blocking |
| P3 | Nice to have, can wait |

Stories on the critical path (no alternative route to the epic's goal) should
always be P1.

### Recursive Decomposition

Sometimes a story is itself too large. That's fine — make it an epic and decompose
again. The tree can go as deep as needed. But:

- Don't pre-decompose. Wait until the specify skill flags a story as too large.
- Shallow is better. Most work should be epic -> stories (one level).
- If you're three levels deep, the original epic might be too ambitious.

---

## Anti-Patterns

### Decomposing Without Discovery

Never decompose an epic that hasn't gone through Phase 1 discovery. The decomposition
will reflect the *description*, not the *design*. Discovery is mandatory for epics.

### Over-Decomposing

Not every epic needs 15 stories. If the seams are natural and each piece is
meaningful, 4-6 stories is fine. More stories = more overhead = more dependency
management. Split enough to parallelize and scope, not more.

### Under-Scoping Stories

A story titled "Core infrastructure" that encompasses the database, config system,
CLI, and logging is not a story — it's an epic. Each story should have a clear,
verifiable deliverable.

### Dependency Spaghetti

If every story depends on every other story, the decomposition is wrong. The
dependency graph should be a DAG with clear levels. If it's not, the seams are
in the wrong places.

### Skipping Human Approval

The decomposition must be approved before stories are handed to the specify skill.
Speccing stories that get restructured later wastes everyone's time.

---

## Exit Criteria

Epic refinement is complete when:
- All stories are created as child beads of the epic
- Dependencies are wired and `bd ready` returns the expected starting points
- Priorities are set
- Human has approved the decomposition
- Epic bead has high-level AC and decomposition overview in design field

When done: "Epic decomposed into N stories. Ready for specification."
Then hand off each child story to the specify skill.
