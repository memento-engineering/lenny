---
name: inspect
description: >
  Code review and integration validation skill. Reviews completed work against
  the original plan, checks code quality, architecture alignment, and test
  coverage. Creates PR on approval. Gates the merge. Use when a bead is in
  code_review, user says "review this", "check the PR", or before merging
  to main.
---

# Review

Review a bead's implementation against its spec in **isolation** so the review reflects the diff and spec, not your accumulated conversation context.

## Dispatch

Run `fs dispatch <id> --skill review`. Parse the single JSON line on stdout. Branch on `via`:

- `via=fs_agent`, `ok=true`: worker ran; refetch `bd show <id>` for state.
- `via=fs_agent`, `ok=false`: worker failed; surface `error` and stop.
- `via=subagent`: dispatch via the Agent tool with the envelope's `subagent_type`, `description`, and `prompt`.
- `via=none`: surface `error` verbatim and stop.

Never execute the review process body in this conversation.

## What This Skill Doesn't Do Itself

This skill body is a **dispatcher**. The full review process — verifying acceptance criteria, code quality, test coverage, then PR creation — lives in `references/process.md`. The dispatcher never executes the process directly; one of the two isolated tiers always handles it (or the skill errors out at the failure-mode step).
