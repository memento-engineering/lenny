---
name: marshal-process
description: Full supervisor cycle — scan, validate, stale check, dispatch builds, monitor, merge approved, notify, report.
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
5b. MERGE APPROVED   -> fs merge each code_review bead carrying review=approved
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
keeps the binary current. Every merge the marshal performs goes through
`fs merge`; there is no out-of-band merge step and no `--admin` shortcut
anywhere in the loop, so the binary never goes stale and CI is never bypassed.

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
It should have already called `fs block --category dependency` with the reason.

```bash
bd comments add <id> "marshal: UNFIT. Agent rejected bead. Spec needs rework." --actor marshal
```

## 5b. Merge Approved

After collecting build results, scan for code_review beads:

```bash
bd list --status=code_review --json
```

By the time the marshal runs, the Committee (`/deliberate --auto`) and `fs route`
have already decided each code_review bead's disposition — the marshal's only job
here is to **land the approved ones**. For each code_review bead, branch on its
`review=` state (set by `fs route --apply`):

- **`review=approved`** — run `fs merge <id>` (see "Merge on APPROVED" below). Merge
  these **one at a time**, even when the build wave ran in parallel.
- **No `review=` state and no `grade:*` labels** — this bead hasn't been to the
  Committee yet. That's `/deliberate --auto`'s job, not the marshal's (the marshal
  is a build/merge floor, not a chair). Note it in the report — "N code_review beads
  await the Committee — run `/deliberate --auto` or `/factory`" — and move on.
- **Any other state** (`grade:*` labels present but `review=` ≠ `approved`, or `fs
  route` already routed the bead onward to `ready` / `in_spec` / `draft` / `blocked`,
  or it self-looped `code_review` with `[human]`) — `fs route` already handled it. A
  bead routed to `ready` re-enters the build queue the marshal scans in Step 1; a
  `[human]` self-loop is a notify (Step 5c), not a re-dispatch; everything else has
  left the floor. The marshal **re-dispatches nothing** — `fs route` does the routing
  (ADR 0004/0005, now enforced at the code phase). Its only code-review actions are:
  merge-the-approved, surface a `[human]` self-loop, and the circuit breaker below.

### What `fs route` already did

`fs route --apply` ran on each code_review bead during deliberation and chose its
disposition — the marshal never transitions a code_review bead itself:

| `fs route` outcome | bead state | marshal action |
|---|---|---|
| passing grades | `code_review`, `review=approved` | `fs merge <id>` (below) |
| rebuild (any D/F default) | `ready`, `fs-route: REBUILD.` comment, grade labels kept | nothing now — Step 1 SCAN re-picks it next cycle; the bitsmith reads the `fs-route: REBUILD.` comment + `grade:*` labels on claim (the `/forge` hook) |
| respec (`spec-adherence` issue traced to the spec) | `in_spec`, grade labels cleared | nothing — the architect re-specs; the bead re-enters the Committee later |
| decompose (`scope-creep==F` → spec was too big) | `draft`, decompose comment | nothing — decomposition is design work; a human (or `/discover`) splits it |
| `regression-risk==F` | `blocked` | escalate — notify, human (Step 5c) |
| grade-spread ≥ 3, or `scope-creep==F` ambiguous | `code_review` self-loop, `capabilities=[human]` | escalate — notify, human (Step 5c) |

The marshal re-dispatches nothing on a rework outcome: `fs route` already moved the
bead to the station that handles it, and a later cycle picks it up. There is no
per-bead retry-budget counter; the circuit breaker (below) and `fs route`'s
`spread ≥ 3` / `scope-creep==F` escalations are the only bounds.

### Merge on APPROVED

Merge `code_review` beads **one at a time** — even when the build wave ran in
parallel, the merge step is serial. Each `fs merge` rebases the bead's worktree
branch onto the just-updated `main` *before* it merges (`factoryskills-1ql`), so a
wave of N parallel builds that all touched a shared file (a barrel, a root config,
`.beads/issues.jsonl`) lands without the parent session hand-resolving rebases.

On a code_review bead carrying `review=approved` (set by `fs route --apply` on
passing `code-review@v1` grades), the marshal runs:
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

`fs merge` gates on green CI before merging — it runs `gh pr checks` and refuses
to merge if any check is failing or still pending, naming the offenders in the
error. It never passes `--admin` to `gh pr merge` unless invoked with
`--force-unsafe`. **The marshal must never pass `--force-unsafe`**: a merge past
failing checks is a human decision, not a loop decision. Just call `fs merge <id>`
and let it gate; if checks aren't green it errors and the marshal surfaces the
open PR via the `pr-ready` notification (Step 5c) and moves on.

If `fs merge` *fails*, the marshal first asks **why**, because a clean (approved)
bead whose merge fails is not the same thing as a broken merge step:

- **Merge conflict / red required check** — `fs merge` rebases the worktree branch
  onto current `main` first (`factoryskills-1ql`); if that rebase conflicts it runs
  `git rebase --abort`, records `merge-blocked: conflict` on the bead itself, and
  errors *without* merging. So when you see that error / comment, the auto-rebase
  could not resolve the overlap — a human (or a `rebuild` re-dispatch with the
  conflict as build context — the `detect-and-re-dispatch` fallback) must finish it.
  If a required CI check is red instead, `fs merge` errors before merging; add
  `merge-blocked: ci-red` if it isn't already there. Either way the bead stays in
  `code_review`, it is *not* `needs_work`, and you do *not* `fs reject`: surface via
  the `pr-ready` / `merge-blocked` notification (Step 5c) and move on.
- **Genuine error** (anything other than a conflict / red check / clean platform
  refusal — e.g. a `bd close` false-block on a `recorded` ancestor, still real for
  some beads per `factoryskills-92iq`) — the marshal **surfaces the failure and
  escalates** (notify, human, Step 5c). It does NOT report success — a bead orphaned
  in `code_review` after a half-completed merge is exactly the failure
  `factoryskills-gmah` filed.

`fs merge` is itself transactional now (`factoryskills-0vmp`): it does not tear
down the worktree or branch, and prints no success line, unless BOTH the merge
*and* `bd close` succeeded — so a bead orphaned in `code_review` after a failed
close can simply be re-merged (`fs merge` is idempotent once the PR is merged).

Neither path uses `needs_work`: a merge conflict is a rebase situation, a genuine
error is a human-escalation situation, and `needs_work` is not a state the marshal
ever sets — `fs route` owns the rework transitions, and a merge problem is a rebase
or escalation situation, never `needs_work`.

### Circuit breaker

Before letting a code_review bead re-enter the build queue (or before reporting it
as awaiting more work), check its history: count the `fs-route: REBUILD.` comments
on it (actor `fs-route` — each one marks a `code_review → ready` round-trip back
toward the bitsmith). If there are **3 or more**, do not let it loop a fourth time:
mark it escalated and notify (Step 5c). A bead this stuck needs a human, not another
build pass.

There is no per-bead retry-budget counter beyond this — the circuit breaker plus
`fs route`'s `spread ≥ 3` / `scope-creep==F` / `regression-risk==F` escalations are
the only bounds.

## 5c. Notify

For each outcome from Steps 5 and 5b that needs human attention, emit a PushNotification. Silent outcomes update bead state only.

### Notify (human attention required)

| Event | When | Command |
|---|---|---|
| Build blocked                          | build agent set bead to blocked                              | fs notify <id> --event build-blocked --reason "..." |
| code_review needs a human (`[human]`)  | `fs route` self-looped a code_review bead with capabilities=[human] (grade-spread ≥ 3 or scope-creep=F) | fs notify <id> --event escalated --reason "code-review grades disagree / scope-creep=F — human re-grade or re-route" |
| Approved → merge refused               | team-repo branch protection / CI gate refused the merge      | fs notify <id> --event pr-ready --pr-url "..." |
| Approved → merge-blocked               | `fs merge` hit a conflict / red required check (recorded `merge-blocked: conflict\|ci-red`); routes to rebase-and-retry, not an escalation | fs notify <id> --event pr-ready --pr-url "..." |
| Approved → merge failed                | `fs merge` errored for a genuine reason (e.g. bd close false-block) — distinct from `merge-blocked` | fs notify <id> --event escalated --reason "..." |
| Circuit breaker ESCALATED              | 3+ REBUILD round-trips                                       | fs notify <id> --event escalated |

Pipe to Claude Code's PushNotification tool: `PushNotification "$(fs notify ...)"`.

### Silent (no notification)

- Build COMPLETE -> bead is now code_review; next cycle's Step 5b picks it up.
- code_review bead routed to ready by fs route -> next cycle's Step 1 SCAN re-picks it for the bitsmith.
- Approved + `fs merge` succeeded -> bead is now closed, PR merged; nothing to notify.

### Escalation triggers

The marshal escalates to a human **only** on:
- a `fs route` `[human]` self-loop on a code_review bead (grade-spread ≥ 3, or `scope-creep==F`),
- the 3-cycle circuit-breaker trip,
- a build `blocked` outcome,
- an `fs merge` genuine-error failure (not a clean team-repo refusal, not a `merge-blocked` conflict — an actual error),
- genuine divergence: an out-of-envelope lifecycle transition, an out-of-worktree
  write, or an unexpected tool invocation by a worker.

Everything else — rework dispositions `fs route` already moved, slow-but-running
agents, ready beads, code_review beads — the marshal drives forward by default.
There is no per-bead retry-budget counter; the circuit breaker and `fs route`'s
escalation rules are the only bounds.

## 6. Report

Reporting depends on invocation mode:

- **Single-shot** (`/marshal` once): print the cycle summary below.
- **Loop mode** (`/loop 10m /marshal`): suppress the printed report. Notifications from Step 5c are the only output. Detect loop mode via the absence of an interactive caller — when the parent does not request the report inline, skip it.

Cycle summary format (single-shot only):

```
Supervisor cycle complete.
  Dispatched build: 2 (bead-xxx, bead-yyy)
  Build complete:    1 (bead-xxx -> code_review)
  Merged:            1 (bead-zzz -> closed, PR #42)
  Merge refused:     0 (team-repo branch protection — PR left open)
  Await Committee:   1 (bead-aaa -- code_review, no grades — run /deliberate --auto or /factory)
  Build blocked:     1 (bead-yyy -- missing API dependency)
  Stale:             1 (bead-www -- in_progress 45 min, no updates)
  Escalated:         0
```

If nothing happened, report that too:

```
Supervisor cycle complete. Nothing to do.
  Ready: 0 | In Progress: 0 | Code Review: 0 | Blocked: 0 | Stale: 0
```
