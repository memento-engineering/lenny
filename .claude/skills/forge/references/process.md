
# Build

Claim a bead. Build it. Ship it. Signal done.

## Flow

```
1. CLAIM     → fs forge <id>
2. VALIDATE  → check required sections exist
3. BLOCK     → if invalid: fs block <id> --category dependency "...", exit
4. EXECUTE   → follow implementation plan step by step
5. VERIFY    → run validation plan
6. COMPLETE  → git push, fs done <id>
```

See [references/bead-contract.md](references/bead-contract.md) for the full claim, validate, block, and completion protocol.

## Startup Assertion

**Before doing anything else**, verify you're in the right place.

```bash
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  # Wrong branch — should be in a worktree on a feature branch
  fs block <id> --category ergonomic "On $CURRENT_BRANCH, not a feature branch — worktree may not be set up"
  # EXIT IMMEDIATELY
fi
```

**Why:** Without this guard, a misconfigured workspace causes commits to the wrong branch. The damage is hard to undo and the bead gets marked complete despite no work landing in the right place.

## Claiming Work

```bash
# See what's ready
fs status

# Claim a specific bead (sets up worktree + feature branch)
fs forge <id>

# Or claim the next ready bead
fs forge
```

`fs forge` creates `.worktrees/<bead-id>/` with a feature branch `fs/<id>/<title>` and sets the bead to `in_progress`. The worktree is your isolated workspace.

**Note:** If `fs agent` launched you, the worktree and claim are already done — `fs forge` will report the bead is already `in_progress`. Verify with `git branch --show-current` and proceed to validation.

## Readiness Validation

After claiming, read the full bead spec:

```bash
bd show <id>
```

Verify the bead has the required sections:

1. `## Acceptance Criteria` — at least one `- [ ]` item
2. `## Implementation Plan` — at least one numbered step
3. `## Validation Plan` — at least one validation item

**If any section is missing or empty:** reject immediately.

```bash
# Spec is incomplete — can't proceed
fs block <id> --category dependency "Missing <section>. Cannot build without it."
# EXIT — do not attempt implementation
```

## Executing the Plan

Follow the implementation plan step by step:

1. Read the full plan before starting
2. Execute each step in order — never skip ahead
3. Commit after each logical unit using conventional commits (`feat:`, `fix:`, `test:`, `refactor:`)
4. After each significant step, verify existing tests still pass
5. If a step is unclear — do not guess. Report blocked.

### TDD When Specified

If the implementation plan includes test-first steps:

1. Write the failing test
2. **Verify it fails** (mandatory — never skip)
3. Write minimal implementation to pass
4. Verify it passes
5. Refactor if needed (keep tests green)
6. Commit

See [references/test-driven-development.md](references/test-driven-development.md) for the full protocol.

## When to Stop

**STOP and report blocked when:**
- A step is ambiguous and guessing could waste work
- A dependency is missing (package, API, file that should exist)
- Tests fail repeatedly and the fix isn't obvious
- The plan contradicts itself

```bash
# Comment with details for the human
bd comments add <id> "bitsmith: BLOCKED/<category>. <specific description>" --actor bitsmith

# Block with categorised reason (transient | dependency | ergonomic)
fs block <id> --category <category> "<description>"
```

## Handling Review Feedback

When re-dispatched after a review rejection, the bead will have a review comment with detailed findings.

### On Re-Dispatch After Rejection

1. **Read the most recent review comment:**
   ```bash
   bd comments list <id>
   ```
   Look for the latest comment from the `inspector` actor starting with `inspector: REBUILD.`, `inspector: RESPEC.`, or `inspector: DECOMPOSE.` (or, on legacy beads, the `review` actor with `Review: CHANGES REQUESTED.` — recognised during the deprecation window).

2. **Parse the findings** — review comments include file/line references, severity (Critical, Important, Suggestion), and recommendations.

3. **Address all Critical and Important issues.** Suggestions are optional but encouraged.

4. **Commit fixes with clear references:**
   ```bash
   git commit -m "fix: address review feedback — <summary>"
   ```

5. **Do NOT re-run the entire implementation plan.** Only address the specific findings. The previous implementation is already committed.

### Review History Awareness

If multiple rejection comments exist, read them all to understand recurring themes. Repeated rejection on the same issue suggests a misunderstanding of requirements — comment on the bead to flag the ambiguity rather than guessing again.

## Running the Validation Plan

After implementation is complete:

1. Execute every item in the validation plan
2. All automated tests must pass
3. Note results in bead comment
4. If validation fails and the fix is obvious — fix it and re-run
5. If validation fails and the fix isn't obvious — report blocked

## Signaling Completion

When all validation passes:

```bash
# Push the working branch
git push -u origin <branch>

# Signal done — verifies push, transitions to code_review
fs done <id>
```

Agent does **not** create PRs, merge, or close beads. `fs done` transitions to `code_review` and adds a completion comment.

## Craft Methodology References

Load on-demand — don't read all of them up front.

| When | Load |
|------|------|
| Encountering any bug or test failure | [references/systematic-debugging.md](references/systematic-debugging.md) |
| Writing new code or fixing bugs | [references/test-driven-development.md](references/test-driven-development.md) |
| About to claim work is done | [references/verification-before-completion.md](references/verification-before-completion.md) |
| Receiving review feedback | [references/receiving-code-review.md](references/receiving-code-review.md) |
| Implementation complete, deciding how to integrate | [references/finishing-a-development-branch.md](references/finishing-a-development-branch.md) |
| Setting up or working in isolated workspace | [references/using-git-worktrees.md](references/using-git-worktrees.md) |
| Claiming, validating, or completing beads | [references/bead-contract.md](references/bead-contract.md) |

Supporting references (loaded by the above):
- [references/root-cause-tracing.md](references/root-cause-tracing.md) — trace bugs backward through call stack
- [references/defense-in-depth.md](references/defense-in-depth.md) — validate at every layer
- [references/condition-based-waiting.md](references/condition-based-waiting.md) — replace arbitrary timeouts
- [references/testing-anti-patterns.md](references/testing-anti-patterns.md) — common test mistakes to avoid

## Refactor Tracking

When implementation reveals code that needs refactoring:

1. **Don't refactor inline.** Stay focused on the current bead.
2. Create a refactor bead to track it:
   ```bash
   fs discover "Refactor: <what>" --type task
   ```
3. Continue current work. The refactor is tracked separately.
4. If the refactor **blocks** current work, link it and report blocked:
   ```bash
   bd dep add <current-bead-id> <refactor-bead-id>
   bd comments add <current-bead-id> "bitsmith: BLOCKED/dependency. need refactor <refactor-bead-id> first" --actor bitsmith
   ```

## Actor Identity

Every direct `bd` command uses `--actor bitsmith` for audit trail:

```bash
bd comments add <id> "bitsmith: BLOCKED/<category>. ..." --actor bitsmith
bd comments add <id> "bitsmith: <SIGNAL>. Implementation complete. ..." --actor bitsmith
```

`fs` commands (like `fs done`, `fs block`) already tag as `"bitsmith"`.

## What You Don't Do

- **Pick your own work** — a human or supervisor assigns it, or you claim the next ready bead
- **Spawn sub-agents** — you are the worker
- **Make architectural decisions** — if the plan is ambiguous, reject or block
- **Skip validation** — if tests fail and can't be fixed, report blocked
- **Review code** — that's the inspect skill
- **Merge to main** — that's `fs merge`
