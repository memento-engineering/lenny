name: finishing-a-development-branch
description: Use when implementation is complete and all tests pass — guides completion via fs done, PR creation, or cleanup

# Finishing a Development Branch

## Overview

Guide completion of development work by presenting clear options and handling the chosen workflow.

**Core principle:** Verify tests → Present options → Execute choice → Clean up.

## The Process

### Step 1: Verify Tests

**Before presenting options, verify tests pass:**

```bash
# Run the project's test suite
go test ./...    # or npm test, cargo test, pytest, etc.
```

**If tests fail:** Stop. Don't proceed to Step 2. Fix or report blocked.

**If tests pass:** Continue to Step 2.

### Step 2: Determine Base Branch

```bash
git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null
```

### Step 3: Present Options

Present exactly these options:

```
Implementation complete. What would you like to do?

1. Push and signal done (fs done <id>) — transitions to pending_review
2. Push and create a Pull Request
3. Keep the branch as-is (I'll handle it later)
4. Discard this work
```

### Step 4: Execute Choice

#### Option 1: Signal Done (Default for bead workflow)

```bash
git push -u origin <branch>
fs done <id>
```

`fs done` verifies the push, adds a completion comment, and transitions to `pending_review`.

#### Option 2: Push and Create PR

```bash
git push -u origin <branch>

gh pr create --title "<title>" --body "$(cat <<'EOF'
## Summary
<2-3 bullets of what changed>

## Test Plan
- [ ] <verification steps>
EOF
)"
```

Then signal done if in bead workflow: `fs done <id>`

#### Option 3: Keep As-Is

Report: "Keeping branch `<name>`. Worktree preserved at `<path>`."

**Don't clean up worktree.**

#### Option 4: Discard

**Confirm first:**
```
This will permanently delete:
- Branch <name>
- All commits since branching
- Worktree at <path>

Type 'discard' to confirm.
```

Wait for exact confirmation.

### Step 5: Cleanup Worktree

**For Options 1, 2, 4:** The worktree can be removed after completion.

**For Option 3:** Keep worktree intact.

Note: `fs merge` (v0.2) will handle worktree cleanup automatically on merge.

## Quick Reference

| Option | Push | Signal Done | Keep Worktree | Cleanup Branch |
|--------|------|-------------|---------------|----------------|
| 1. fs done | Yes | Yes | No | After merge |
| 2. Create PR | Yes | Optional | No | After merge |
| 3. Keep as-is | No | No | Yes | No |
| 4. Discard | No | No | No | Yes (force) |

## Common Mistakes

- **Skipping test verification** — merging or pushing broken code
- **Open-ended questions** — "What should I do?" instead of structured options
- **Automatic worktree cleanup** — removing worktree when it might still be needed
- **No confirmation for discard** — accidentally deleting work

## Red Flags

**Never:**
- Proceed with failing tests
- Merge without verifying tests on result
- Delete work without typed confirmation
- Force-push without explicit request

## Integration

**Pairs with:**
- **[using-git-worktrees.md](using-git-worktrees.md)** — cleans up worktree created by `fs build`
