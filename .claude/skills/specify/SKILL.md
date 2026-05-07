---
name: specify
description: >
  Write concrete, implementation-ready specifications. Translates an approved
  design into acceptance criteria, implementation plan, and validation plan.
  Enforces size limits and lint gates. Use when user says "write the spec",
  "specify this", or after discovery is complete.
---

# Specify

Write the spec for a bead in **isolation** so the spec reflects the bead, not your accumulated conversation context.

## Dispatch

Run `fs dispatch <id> --skill specify`. Parse the single JSON line on stdout. Branch on `via`:

- `via=fs_agent`, `ok=true`: worker ran; refetch `bd show <id>` for state.
- `via=fs_agent`, `ok=false`: worker failed; surface `error` and stop.
- `via=subagent`: dispatch via the Agent tool with the envelope's `subagent_type`, `description`, and `prompt`.
- `via=none`: surface `error` verbatim and stop.

Never execute the specify process body in this conversation.

## What This Skill Doesn't Do Itself

This skill body is a **dispatcher**. The full specify process — writing acceptance criteria, implementation plan, validation plan, lint gating — lives in `references/process.md`. The dispatcher never executes the process directly; one of the two isolated tiers always handles it (or the skill errors out at the failure-mode step).
