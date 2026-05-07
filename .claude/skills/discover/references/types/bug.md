name: bug-discovery
description: Use when discovering bugs — repro-focused discovery with severity assessment, root cause investigation, and blast radius analysis

# Bug — Discovery

Bugs focus on understanding *what's broken* and *why*, not designing new features.
Discovery is shorter but has different priorities.

## Phase 1 — Discovery

**First:** Follow [../brainstorming.md](../brainstorming.md) for the standard discovery process,
with the following adjustments.

### Bug-Specific Discovery Questions

Replace the standard "propose 2-3 approaches" with root cause investigation:

1. **Reproduce** — Can we reproduce it? What are the exact steps?
2. **Severity** — Who's affected? How badly? Is there a workaround?
3. **Root cause** — What's the hypothesis? Where in the codebase?
4. **Blast radius** — What else might be affected by the same issue?
5. **Fix approach** — What's the simplest fix? Are there alternatives?

### Differences from Feature Discovery

- **No design approval gate.** Bugs don't need a "design" — they need a fix strategy.
  Discovery exits when the root cause is understood and the fix approach is agreed.
- **Shorter cycle.** Most bugs need 1-3 questions, not a full brainstorming session.
- **Skip discovery** when the bug is obvious (typo, off-by-one, missing null check)
  and the fix is self-evident. Go straight to the specify skill.

### Exit Criteria

Bug discovery is complete when:
- Root cause is identified (or best hypothesis stated)
- Fix approach is agreed
- Blast radius is understood
- Severity is assessed

When done: "Root cause identified. Moving to specification."
Then hand off to the specify skill.
