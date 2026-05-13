---
name: marshal-process
description: Full supervisor cycle — scan, validate, stale check, dispatch, monitor, review dispatch, notify, report.
---

# Supervise — Process

Each invocation runs one supervisor cycle. Cycles are idempotent — safe to re-run or loop.

```
0. SYNC              -> git pull --rebase --autostash (refresh .beads + merged skills/binary)
1. SCAN              -> find ready beads (max 3)
2. VALIDATE          -> lint each candidate
3. STALE             -> flag stuck in_progress beads
4. DISPATCH BUILD    -> spawn build agents (parallel when independent)
5. MONITOR BUILD     -> collect build agent results
5b. DISPATCH REVIEW  -> spawn review agents on code_review beads
5c. NOTIFY           -> PushNotification for human-needed events
6. REPORT            -> summarize cycle (single-shot only; suppressed in /loop)
```

## 0. Sync

```bash
git pull --rebase --autostash
```

Refresh `.beads/issues.jsonl` and any skill/binary changes merged since the
last tick — a co-driving session (a human, or another loop) feeds the queue,
and the cycle must see it. `git:*` is already allowlisted.

No `go build -o $(command -v fs) ./cmd/fs` is needed after the pull. `fs merge`
rebuilds the `fs` binary whenever the merge touched `fs` source
(`factoryskills-rv3s`), so a merge done by *this* marshal's auto-merge (Step 5b)
keeps the binary current. The only stale-binary gap was a raw `gh pr merge` done
out of band — which Step 5b's auto-merge eliminates.

## 1. Scan

```bash
fs ready --auto
```

This prints, one ID per line, every bead that is currently buildable —
beads in `ready` status (Committee-approved and ready to build). No state
is mutated; the picked beads only transition to `in_progress` when the
build agent claims them.

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

When the bead carries `grade:*` labels, `fs forge` recomputes the capability set and refuses the claim if the dispatched builder's declared capability isn't in it (set `--capability` or `claimant_capability` in `.factoryskills/config` to match the bitsmith you're dispatching).

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

The inspector returns one of these verdicts. `fs verdict` records it and drives
the next state — the marshal does not transition the bead itself:

| Verdict | Bead state after `fs verdict` | Marshal action |
|---|---|---|
| APPROVED   | code_review (still)  | run `fs merge <id>` — see "Merge on APPROVED" below |
| REBUILD    | ready                | nothing now; next cycle's Step 1 SCAN re-picks it; the bitsmith reads the prior `inspector: REBUILD.` comment as build context (the `/forge` side is `factoryskills-thxf`) |
| RESPEC     | committee_review     | nothing now; next cycle's deliberate step re-grades it with the inspector findings as evidence (ADR 0005); `fs route` will most often send it to `in_spec` for the architect |
| DECOMPOSE  | committee_review     | nothing now; re-graded next cycle; the `scope` rubric grades F → `fs route` sends it to `draft` with the decompose hint → a human (or the marshal, if it judges the split mechanical) spawns the children. Default: escalate — decomposition is design work, not a marshal action |
| UNFIT / circuit-breaker ESCALATED | code_review (still) | escalate — notify, human (Step 5c) |
| BLOCKED (build) | blocked          | escalate — notify, human (Step 5c) |

On REBUILD / RESPEC / DECOMPOSE the marshal **re-dispatches nothing** — `fs
verdict` already moved the bead to the station that handles it (`ready` for the
next bitsmith, `committee_review` for the next deliberation), and the loop picks
it up on a later turn. The marshal's only post-verdict actions are
merge-on-APPROVED and escalate-on-{UNFIT, BLOCKED, circuit-breaker}. There is no
per-bead retry-budget counter; the 3-cycle review circuit breaker (below, and in
`skills/inspect/references/process.md`) plus `fs route`'s `decisions==F` /
`spread≥3` escalation are the only bounds.

### Merge on APPROVED

On an inspector APPROVED verdict, the marshal runs:
```bash
fs merge <id>
```
Honor `branch-protection-is-the-merge-gate` — the platform's branch protection is
the merge gate, not a marshal-side rule:

- **Solo repo** (no required reviewers / status checks): `fs merge` runs to
  completion — squash-merge, worktree cleanup, `bd close`, and (post-`factoryskills-rv3s`)
  a rebuild of the `fs` binary if the merge touched `fs` source. The bead lands
  `closed`. Notify "merged" (Step 5c) — or suppress it in loop mode.
- **Team repo** (required reviewers, CI gates): `gh` refuses the merge; `fs merge`
  reports that back; the bead **stays `code_review`**. The marshal surfaces the
  open PR via the `pr-ready` notification (Step 5c) and moves on. There is no
  "always stop at PR-open" rule — the platform gate is the safety net.

`fs merge` does its own CI-status check before merging (`factoryskills-vhq` adds
that guard inside `fs merge`) — the marshal does not need to, and must not, force a
merge past failing checks; just call `fs merge` and let it gate.

If `fs merge` *fails* (an error rather than a clean platform refusal — e.g. a
`bd close` false-block on a `recorded` ancestor, still real for some beads per
`factoryskills-92iq`), the marshal **surfaces the failure and escalates** (notify,
human, Step 5c). It does NOT report success — a bead orphaned in `code_review`
after a half-completed merge is exactly the failure `factoryskills-gmah` filed.

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
| Review APPROVED → merge refused | team-repo branch protection / CI gate refused the merge | fs notify <id> --event pr-ready --pr-url "..." |
| Review APPROVED → merge failed  | `fs merge` errored (e.g. bd close false-block)          | fs notify <id> --event escalated --reason "..." |
| Review REJECTED            | review rejected                    | fs notify <id> --event review-rejected --reason "..." |
| Circuit breaker ESCALATED  | 3+ review cycles                   | fs notify <id> --event escalated |

Pipe to Claude Code's PushNotification tool: `PushNotification "$(fs notify ...)"`.

### Silent (no notification)

- Build COMPLETE -> bead is now code_review; next cycle's Step 5b picks it up.
- Review dispatched -> the supervisor is still working; loop continues.
- Review APPROVED + `fs merge` succeeded -> bead is now closed, PR merged; nothing to notify.

### Escalation triggers

The marshal escalates to a human **only** on:
- a `fs route` `[human]` verdict (grade spread ≥ 3, or `decisions==F`),
- the 3-cycle review circuit-breaker trip,
- an `unfit` (escalated) review verdict,
- a build `blocked` outcome,
- an `fs merge` failure (not a clean team-repo refusal — an actual error),
- genuine divergence: an out-of-envelope lifecycle transition, an out-of-worktree
  write, or an unexpected tool invocation by a worker.

Everything else — rework verdicts, slow-but-running agents, ready beads,
code_review beads — the marshal drives forward by default. There is no per-bead
retry-budget counter; the circuit breaker and `fs route`'s escalation rules are
the only bounds.

## 6. Report

Reporting depends on invocation mode:

- **Single-shot** (`/marshal` once): print the cycle summary below.
- **Loop mode** (`/loop 10m /marshal`): suppress the printed report. Notifications from Step 5c are the only output. Detect loop mode via the absence of an interactive caller — when the parent does not request the report inline, skip it.

Cycle summary format (single-shot only):

```
Supervisor cycle complete.
  Dispatched build: 2 (bead-xxx, bead-yyy)
  Dispatched review: 1 (bead-zzz)
  Build complete:    1 (bead-xxx -> code_review)
  Review approved:   1 (bead-zzz -> merged, closed, PR #42)
  Merge refused:     0 (team-repo branch protection — PR left open)
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
