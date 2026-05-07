name: default-discovery
description: Use for standard feature, task, and chore discovery — follows brainstorming process with type-specific notes

# Default — Discovery (feature, task, chore)

Standard discovery for work items that don't have type-specific handling.

## Phase 1 — Discovery

Follow [../brainstorming.md](../brainstorming.md). No type-specific adjustments.

### Exit Criteria

Same as standard discovery:
- Design approved by human (explicitly, not assumed)
- No open questions that would block specification

When done: "Design approved. Moving to specification."
Then hand off to the specify skill.

### Notes by Type

**feature** — Full discovery. Explore approaches, propose alternatives, get approval.

**task** — Often pre-scoped (refactoring, documentation, test coverage). Discovery
can be brief — confirm scope and approach, then proceed. Skip only if the task is
genuinely unambiguous.

**chore** — Dependency updates, tooling changes, CI fixes. Minimal discovery.
Confirm what's changing and verify no side effects. Often skippable.
