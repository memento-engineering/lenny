name: requesting-review
description: Use when setting up context for a code review or requesting a review of completed work

# Requesting Code Review

How to set up and request a review of completed work.

**Core principle:** Review early, review often.

## When to Request Review

**Mandatory:**
- After completing a bead (`fs done` transitions to `pending_review`)
- Before merge to main

**Optional but valuable:**
- When stuck (fresh perspective)
- Before refactoring (baseline check)
- After fixing a complex bug
- After each significant implementation step

## Setting Up Review Context

The reviewer needs two things: the plan and the diff.

### 1. Get the Plan

```bash
bd show <id>
```

This provides: description, acceptance criteria, implementation plan, validation plan, and all comments.

### 2. Get the Diff

```bash
cd .worktrees/<bead-id>/

# All changes since branching from main
BASE_SHA=$(git merge-base main HEAD)
HEAD_SHA=$(git rev-parse HEAD)
git diff $BASE_SHA $HEAD_SHA
```

For a quick summary:
```bash
git diff --stat $BASE_SHA $HEAD_SHA
```

### 3. Provide Context

When requesting a review (from a human or another agent), include:
- **What was implemented** — brief summary
- **Bead ID** — for the full plan
- **Branch** — where the work lives
- **Base and head SHAs** — for the exact diff range

## Acting on Feedback

After receiving review feedback, address issues in priority order:

1. **Critical** — fix immediately, these block merge
2. **Important** — fix before proceeding
3. **Suggestion** — note for later, optional

For each fix:
- Address one item at a time
- Test after each fix
- Commit with clear reference to the feedback

```bash
git commit -m "fix: address review feedback — <summary of what changed>"
```

## Red Flags

**Never:**
- Skip review because "it's simple"
- Ignore Critical issues
- Proceed with unfixed Important issues
- Argue with valid technical feedback without evidence

**If reviewer seems wrong:**
- Push back with technical reasoning
- Show code or tests that prove your point
- Request clarification before assuming
