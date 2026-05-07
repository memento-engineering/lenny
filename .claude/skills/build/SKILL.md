---
name: build
description: >
  Portable implementation skill for coding agents. Claims a bead, validates
  readiness, executes the implementation plan step by step, runs the validation
  plan, and signals completion. Rejects beads with missing or ambiguous specs.
  Use when a bead is ready, user says "build this", "implement", "fix this",
  or "work on bead <id>".
---

# Build

Claim a bead. Build it. Ship it. Signal done — in **isolation** so the build process operates on the bead's spec and worktree, not on the parent conversation's accumulated context.

## Dispatch

Run `fs dispatch <id> --skill build`. Parse the single JSON line on stdout. Branch on `via`:

- `via=fs_agent`, `ok=true`: worker ran; refetch `bd show <id>` for state.
- `via=fs_agent`, `ok=false`: worker failed; surface `error` and stop.
- `via=subagent`: dispatch via the Agent tool with the envelope's `subagent_type`, `description`, and `prompt`.
- `via=none`: surface `error` verbatim and stop.

Never execute the build process body in this conversation.

## What This Skill Doesn't Do Itself

This skill body is a **dispatcher**. The full build process — claim, validation, TDD, completion signaling, refactor tracking — lives in `references/process.md`. The dispatcher never executes the process directly; one of the two isolated tiers always handles it (or the skill errors out at the failure-mode step).
