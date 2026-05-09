---
name: supervise-process
description: Full supervisor cycle — scan, validate, stale check, dispatch, monitor, review dispatch, notify, report.
---

# Supervise — Process

Each invocation runs one supervisor cycle. Cycles are idempotent — safe to re-run or loop.

```
1. SCAN              -> find ready beads (max 3)
2. VALIDATE          -> lint each candidate
3. STALE             -> flag stuck in_progress beads
4. DISPATCH BUILD    -> spawn build agents (parallel when independent)
5. MONITOR BUILD     -> collect build agent results
5b. DISPATCH REVIEW  -> spawn review agents on code_review beads
5c. NOTIFY           -> PushNotification for human-needed events
6. REPORT            -> summarize cycle (single-shot only; suppressed in /loop)
```

## 1. Scan

```bash
fs ready --auto
```

This prints, one ID per line, every bead that is currently buildable —
either already in `ready` (human-promoted) or in `spec_review` with all
`blocks`-type dependencies closed (auto-dispatch). No state is mutated;
the picked beads only transition to `in_progress` when the build agent
claims them.

Then for each ID, fetch details with `bd show <id> --json` to filter
out epics and to apply the priority cap.

Filter the results:
- **Exclude epics** — epics are containers, not buildable work
- **Cap at 3** — take the highest-priority beads first (lowest priority number)

If no ready beads, skip to Step 3 (stale check) — there may still be stuck
work worth reporting.

## 2. Validate

For each candidate:

```bash
fs lint <id>
```

If lint fails, reject the bead and remove it from the dispatch list:

```bash
bd comments add <id> "marshal: UNFIT. <lint output>. Fix the spec before this can be dispatched." --actor marshal
bd update <id> --status needs_work
```

Do **not** attempt to fix the bead — that's the human's job (via discover/specify).

## 3. Stale and Blocked Check

### Stale in_progress

```bash
bd list --status=in_progress --json
```

For each, check the `updated_at` timestamp. Flag any bead not updated in the
last 30 minutes as stale. Include in the report but **do not auto-act** — the
human decides (the agent may still be working, just slow).

### Blocked beads

```bash
bd list --status=blocked --json
```

Include in the report. These need human intervention to unblock.

## 4. Dispatch

For each validated bead, run `fs dispatch <id> --skill build` and parse the JSON line on stdout. Branch on `via`:

- `via=fs_agent`, `ok=true`: worker ran; refetch `bd show <id>` for state.
- `via=fs_agent`, `ok=false`: worker failed; record `error` and continue with the next bead.
- `via=subagent`: spawn an Agent subagent using the envelope's `subagent_type`, `description`, and `prompt`.
- `via=none`: surface `error` and stop dispatch for this cycle.

**Independent beads (parallel):** spawn each `fs dispatch` call via Bash `run_in_background`; collect outcomes by re-fetching `bd show <id>`. For `via=subagent` envelopes, batch the resulting Agent tool calls in a single message.

**Dependent beads:** dispatch upstream first; wait for the envelope; then dispatch downstream.

Beads listed by `fs ready --auto` may be in `spec_review` rather than `ready`. Both `fs forge <id>` and `fs agent` accept this via the auto-dispatch lifecycle edge.

## 5. Monitor

Agent subagents return results inline when they finish.

For each result, determine the outcome and record it:

### COMPLETE

The agent ran `fs done` — bead is now `code_review`.

```bash
bd comments add <id> "marshal: APPROVED. Dispatched and completed. Pending review." --actor marshal
```

### BLOCKED

The agent couldn't proceed. It should have already set the bead to
`needs_work` or `blocked` and added a comment.

```bash
bd comments add <id> "marshal: ESCALATED. Agent blocked during implementation." --actor marshal
```

Flag for human attention in the report.

### REJECTED

The agent found the spec was unbuildable (missing sections, contradictions).
It should have already called `fs block --category dependency` (or, if a
review-level verdict, `fs verdict <id> respec|unfit`).

```bash
bd comments add <id> "marshal: UNFIT. Agent rejected bead. Spec needs rework." --actor marshal
```

## 5b. Dispatch Review

Scan for code_review beads after collecting build results:

```bash
bd list --status=code_review --json
```

For each code_review bead, run `fs dispatch <id> --skill review` and parse the JSON line on stdout. Branch on `via`:

- `via=fs_agent`, `ok=true`: worker ran; refetch `bd show <id>` for state.
- `via=fs_agent`, `ok=false`: worker failed; record `error` and continue with the next bead.
- `via=subagent`: spawn an Agent subagent using the envelope's `subagent_type`, `description`, and `prompt`.
- `via=none`: surface `error` and stop review dispatch for this cycle.

**Independent reviews (parallel):** spawn each `fs dispatch` call via Bash `run_in_background`; collect results by re-fetching `bd show <id>`. For `via=subagent` envelopes, batch the resulting Agent tool calls in a single message.

### Outcomes

The inspector returns one of four results:

| Outcome | Bead state after | Next action |
|---|---|---|
| APPROVED | bead closed, PR open | notify human (Step 5c) |
| CHANGES_REQUESTED | needs_work | notify human (Step 5c) |
| REJECTED | needs_work | notify human (Step 5c) |
| BLOCKED | blocked | notify human (Step 5c) |

### Circuit breaker

Before dispatching, check the bead's review history. If the bead has cycled through code_review -> needs_work -> ready -> code_review three or more times, do NOT dispatch a fourth review. Mark as escalated and notify (Step 5c).

Detection: count comments by `--actor inspector` (or legacy `--actor review`) whose body begins with `inspector: RESPEC.`, `inspector: REBUILD.`, `inspector: DECOMPOSE.`, or `inspector: UNFIT.` (or, on legacy beads, `Review: CHANGES REQUESTED.` / `Review: REJECTED.` — recognised during the deprecation window). If >= 3, escalate.

## 5c. Notify

For each outcome from Steps 5 and 5b that needs human attention, emit a PushNotification. Silent outcomes update bead state only.

### Notify (human attention required)

| Event | When | Command |
|---|---|---|
| Build blocked              | build agent set bead to blocked    | fs notify <id> --event build-blocked --reason "..." |
| Review CHANGES_REQUESTED   | review returned changes requested  | fs notify <id> --event review-changes |
| Review APPROVED            | review approved, PR opened         | fs notify <id> --event pr-ready --pr-url "..." |
| Review REJECTED            | review rejected                    | fs notify <id> --event review-rejected --reason "..." |
| Circuit breaker ESCALATED  | 3+ review cycles                   | fs notify <id> --event escalated |

Pipe to Claude Code's PushNotification tool: `PushNotification "$(fs notify ...)"`.

### Silent (no notification)

- Build COMPLETE -> bead is now code_review; next cycle's Step 5b picks it up.
- Review dispatched -> the supervisor is still working; loop continues.

## 6. Report

Reporting depends on invocation mode:

- **Single-shot** (`/supervise` once): print the cycle summary below.
- **Loop mode** (`/loop 10m /supervise`): suppress the printed report. Notifications from Step 5c are the only output. Detect loop mode via the absence of an interactive caller — when the parent does not request the report inline, skip it.

Cycle summary format (single-shot only):

```
Supervisor cycle complete.
  Dispatched build: 2 (bead-xxx, bead-yyy)
  Dispatched review: 1 (bead-zzz)
  Build complete:    1 (bead-xxx -> code_review)
  Review approved:   1 (bead-zzz -> closed, PR #42)
  Review changes:    0
  Build blocked:     1 (bead-yyy -- missing API dependency)
  Stale:             1 (bead-www -- in_progress 45 min, no updates)
  Escalated:         0
```

If nothing happened, report that too:

```
Supervisor cycle complete. Nothing to do.
  Ready: 0 | In Progress: 0 | Code Review: 0 | Blocked: 0 | Stale: 0
```
