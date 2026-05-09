---
name: discover
description: >
  Interactive design discovery before specification. Explore the problem, ask
  clarifying questions, propose approaches, get design approval. Type-specific
  flows for features, bugs, epics, and decisions. Use when user says "let's
  build", "I have an idea", "plan this", "design this", or any creative/design
  work before implementation.
---

# Discover

Explore the problem. Understand what we're building before specifying how.

## Process

### 1. Explore

Understand what exists before proposing what's new.

```bash
# Check for existing work on this topic
fs status
```

Read relevant files, check recent commits. Build context before asking questions.

### 2. Create the Bead

```bash
# Persistent bead (default — for confirmed work)
fs discover "Feature title" --type feature

# Ephemeral bead (for exploration — won't pollute the database)
fs discover "Just an idea" --type feature --ephemeral
```

Types: `feature`, `bug`, `task`, `epic`

**Ephemeral beads (wisps):** Use `--ephemeral` when exploring ideas that may not
lead to real work. Ephemeral beads are automatically cleaned up if not promoted.

When the design is confirmed and you're ready to proceed:
```bash
bd update <id> --persistent
```

### 3. Discovery Conversation

Load the type-specific reference for the bead being worked on. Each reference
builds on the shared discovery process in [references/brainstorming.md](references/brainstorming.md).

| Bead type | Reference | What's different |
|-----------|-----------|-----------------|
| `epic` | [references/types/epic.md](references/types/epic.md) | Discovery + Phase 1b refinement (decomposition into stories) |
| `bug` | [references/types/bug.md](references/types/bug.md) | Repro-focused discovery, root cause investigation |
| `decision` | [references/types/decision.md](references/types/decision.md) | ADR exploration, tradeoff documentation |
| `feature`, `task`, `chore` | [references/types/default.md](references/types/default.md) | Standard discovery |

**If the bead type isn't known yet** (exploring an idea), start with the standard
discovery process. The type will emerge during exploration — retype the bead
when it's clear: `bd update <id> --type epic`

### 4. Hand Off

Once the design is approved, **before** calling `fs specify`:

Write the discovery outcome into the bead so the specify worker has context in isolation:

```bash
bd update <id> --description "One paragraph: what problem this solves and why it needs doing."
bd update <id> --design "Key decisions from the discovery conversation: approach chosen, constraints, what was ruled out and why, any non-obvious implementation notes."
```

Be specific — the specify worker runs in a fresh context with no access to this conversation. If the design field is empty, it will invent scope from the title alone.

Then:

- If the human says "continue", "let's keep going", "specify it", or otherwise signals they want to proceed — run `fs specify <id>` yourself and transition into the specify skill.
- Otherwise, hand off: "Design approved. Run `fs specify <id>` when you're ready to write the spec."

## Exit Criteria

Before handing off, verify:
- Human has **explicitly approved** the design.
- No open questions remain.
- You can articulate what we're building in one sentence.

## Craft Methodology References

Load on-demand during discovery:

| When | Load |
|------|------|
| Starting any discovery conversation | [references/brainstorming.md](references/brainstorming.md) |
| Discovering or decomposing an epic | [references/types/epic.md](references/types/epic.md) |
| Discovering a bug | [references/types/bug.md](references/types/bug.md) |
| Exploring an architectural decision | [references/types/decision.md](references/types/decision.md) |
| Standard feature, task, or chore | [references/types/default.md](references/types/default.md) |

## What You Don't Do Here

- Write acceptance criteria or implementation plans (that's the specify skill).
- Write code (that's the forge skill).
- Run `fs specify` yourself unless the human signals they want to continue.
- Skip discovery because "this is too simple" — discover anyway.
- Ask multiple questions at once — one at a time.
