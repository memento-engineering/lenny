---
name: marshal
description: >
  Factory floor supervisor. Scans for ready beads, validates them, dispatches
  build agents in parallel, monitors completion, merges Committee-approved
  code_review beads, and emits push notifications for human-needed events
  (blocked builds, review feedback, PRs ready to merge, escalations).
  Human-triggered or autonomous via /loop. Use when user says "marshal",
  "dispatch work", "check the floor", or "what needs building".
---

# Supervise

Scan. Validate. Dispatch builds. Monitor. Merge approved. Notify. Report.

The full cycle process lives in `references/process.md`. This file covers
prerequisites, permissions, and invocation. Load `process.md` to execute a
cycle.

## Prerequisites

The supervisor spawns subagents via Claude Code's Agent tool. Subagents inherit permissions from the parent session, so if your session denies Write/Bash, every dispatched build will fail at the first file change.

### Permissions

Add the rules below to `.claude/settings.local.json` (user-scoped, gitignored) or `.claude/settings.json` (project-scoped, checked in):

```json
{
  "permissions": {
    "defaultMode": "auto",
    "allow": [
      "Bash(git:*)",
      "Bash(fs:*)",
      "Bash(./fs:*)",
      "Bash(bd:*)",
      "Bash(go:*)",
      "Bash(cd:*)",
      "Bash(mkdir:*)",
      "Write(//**/.worktrees/**)",
      "Edit(//**/.worktrees/**)"
    ]
  }
}
```

Tighten the `Bash(...)` patterns to the build toolchain your project actually uses (npm, pytest, swift, whatever). The `Write` and `Edit` globs must cover `.worktrees/**` — that's where every build agent operates.

### Parent permission mode

The parent session's mode wins for subagents:

| Parent mode | Subagent behavior |
|---|---|
| `auto` | Subagent inherits `auto`; `permissionMode` in the agent definition is ignored. Use the `allow` list above. |
| `default` | Subagent's own `permissionMode` applies — the bundled `bitsmith` agent declares `bypassPermissions` and needs no allow list. |
| `acceptEdits` / `bypassPermissions` | Parent wins. Subagent inherits the mode. |

If your session is in `auto` mode and subagents still get denied, the missing rule is almost always `Write(//**/.worktrees/**)` or the project-specific build `Bash` command.

## Running a Cycle

Each invocation runs one supervisor cycle. Load and follow
`skills/marshal/references/process.md` step by step.

## Autonomous Loop

```
/loop 10m /marshal
```

In loop mode, the report is suppressed. Notifications from Step 5c of the
cycle are the only output. See `references/process.md` Step 6 for details.

## What You Don't Do

- **Write code** — you dispatch bitsmiths
- **Adjudicate rework** — `fs route` already routes rework dispositions on `code_review` beads (`respec` → `in_spec`, `decompose` → `draft`, `rebuild` → `ready`, plus `blocked` / a `[human]` self-loop); you re-pick the bead on a later cycle, you do not re-dispatch forge or specify
- **Make architectural decisions** — escalate via PushNotification
- **Spawn decompose-children** — escalate; decomposition is design work
- **Dispatch more than 3 builds per cycle** — prevent runaway
- **Act on stale beads** — notify, human investigates
