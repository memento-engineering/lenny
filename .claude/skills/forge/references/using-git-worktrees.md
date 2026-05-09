name: using-git-worktrees
description: Use when starting feature work in a worktree or troubleshooting worktree issues — covers how fs forge creates worktrees and how to work within them

# Using Git Worktrees

## Overview

Git worktrees create isolated workspaces sharing the same repository, allowing work on multiple branches simultaneously without switching.

**In factoryskills**, `fs forge <id>` handles worktree creation automatically. This reference covers working within worktrees and troubleshooting.

## How fs forge Creates Worktrees

```bash
fs forge <id>
```

This creates:
- **Path:** `.worktrees/<bead-id>/`
- **Branch:** `fs/<id>/<sanitized-title>` (kebab-case, max 40 chars)
- **Status:** Bead transitions to `in_progress`

You don't need to create worktrees manually. `fs forge` handles it.

## Working in a Worktree

After `fs forge`, change to the worktree directory:

```bash
cd .worktrees/<bead-id>/
```

From here, all git operations apply to the feature branch:

```bash
git status              # shows changes in worktree
git add <file>          # stage in worktree
git commit -m "feat: ..." # commit on feature branch
git push -u origin <branch>
```

### Verifying You're in the Right Place

```bash
# Should show your feature branch, NOT main
git branch --show-current

# Should show the worktree path
pwd
```

If you're on `main` or `master`, something is wrong. See [Startup Assertion in SKILL.md](../SKILL.md#startup-assertion).

## Safety Verification

### Worktree Directory Is Gitignored

The `.worktrees/` directory must be in `.gitignore` to prevent accidentally committing worktree contents. `fs init` handles this, but verify:

```bash
git check-ignore -q .worktrees 2>/dev/null && echo "ignored" || echo "NOT ignored"
```

If NOT ignored, add it:
```bash
echo '/.worktrees/' >> .gitignore
git add .gitignore && git commit -m "chore: add .worktrees to gitignore"
```

### Running Project Setup

After entering a new worktree, you may need to install dependencies:

```bash
# Auto-detect from project files
[ -f package.json ] && npm install
[ -f Cargo.toml ] && cargo build
[ -f requirements.txt ] && pip install -r requirements.txt
[ -f go.mod ] && go mod download
```

### Verify Clean Baseline

Run tests to ensure the worktree starts clean:

```bash
# Use whatever the project uses
go test ./...
```

If tests fail before you've changed anything, the base branch has issues. Report this.

## Common Mistakes

### Working in the wrong directory

- **Problem:** Running commands from the repo root instead of the worktree
- **Fix:** Always `cd .worktrees/<bead-id>/` after `fs forge`

### Committing to main

- **Problem:** Accidentally working on main instead of the feature branch
- **Fix:** Check `git branch --show-current` before starting work

### Forgetting to push before fs done

- **Problem:** `fs done` requires the branch to be pushed
- **Fix:** Always `git push -u origin <branch>` before `fs done <id>`

### Proceeding with failing baseline tests

- **Problem:** Can't distinguish new bugs from pre-existing issues
- **Fix:** Report failures, get explicit permission to proceed

## Quick Reference

| Situation | Action |
|-----------|--------|
| `.worktrees/` exists | Use it (verify ignored) |
| Tests fail during baseline | Report failures, ask |
| On wrong branch | Stop, verify worktree setup |
| Need dependencies | Auto-detect from project files |

## Integration

**Pairs with:**
- **[finishing-a-development-branch.md](finishing-a-development-branch.md)** — cleanup after work complete
- **[bead-contract.md](bead-contract.md)** — full claim/complete protocol
