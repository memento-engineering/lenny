name: bead-contract
description: Use when claiming, validating, executing, or completing beads — the full protocol for each phase

# Bead Contract — Build Reference

How to claim, validate, execute, and signal completion on beads.

## Claim Protocol

```bash
fs build <id>
```

`fs build` is atomic: creates worktree, sets up feature branch, transitions to `in_progress`. If the bead is already claimed or not in `ready` status, it fails. This prevents double-dispatch.

If claim fails: exit cleanly. Another agent has this work or the bead isn't ready.

## Readiness Validation

After claiming, parse the bead body for required sections:

### Required Sections

| Section | Check | Example |
|---------|-------|---------|
| `## Acceptance Criteria` | Has at least one `- [ ]` item | `- [ ] Server accepts connections` |
| `## Implementation Plan` | Has at least one numbered step | `1. Create main module` |
| `## Validation Plan` | Has at least one list item | `- Unit tests for parser` |

### Validation Logic

```
For each required section:
  1. Find the H2 header in bead body
  2. Check content between this header and the next H2 (or end of body)
  3. Verify at least one matching item exists

If ANY section is missing or empty → REJECT
```

## Rejection Protocol

When validation fails:

```bash
# Reject with specific reason
fs reject <id> "Missing Validation Plan section. Cannot verify implementation."

# EXIT — do not attempt any implementation
```

**Rules:**
- Always state exactly which section is missing or empty
- Never attempt implementation on a rejected bead
- One rejection per issue — if multiple sections are missing, list them all

## Execution Protocol

1. Read the full `## Implementation Plan` before starting
2. Execute steps in order — never skip ahead
3. Each step should result in a working (or at least compiling) state
4. Commit after each logical unit using conventional commits

### Commit Convention

```bash
git commit -m "feat(<scope>): <description>"
git commit -m "test(<scope>): <description>"
git commit -m "refactor(<scope>): <description>"
```

### Handling Ambiguity

If a step is unclear:
- Do NOT guess or improvise
- Report blocked with the specific question

```bash
bd comments add <id> "BLOCKED: Step 3 says 'implement the handler' but doesn't specify which protocol or method signature." --actor build
fs reject <id> "Blocked: ambiguous step 3"
```

## Completion Protocol

After all implementation and validation passes:

```bash
# Push the working branch
git push -u origin <branch>

# Signal done — transitions to pending_review
fs done <id>
```

**Rules:**
- Agent never creates PRs or merges branches
- Agent never closes beads
- Agent pushes the branch and lets `fs done` handle the transition

## Blocker Protocol

When hitting an unresolvable issue during implementation:

```bash
# Comment with details
bd comments add <id> "BLOCKED: <specific description of what's blocking and why>" --actor build

# Reject with reason
fs reject <id> "Blocked: <description>"

# Do NOT close the bead
# Do NOT continue with other steps
# Exit and let the human resolve
```

## Status Summary

| Situation | Action | Exit? |
|-----------|--------|-------|
| Claim succeeds | Continue to validation | No |
| Claim fails (not ready / already claimed) | Exit cleanly | Yes |
| Validation passes | Continue to execution | No |
| Validation fails | Reject with comment | Yes |
| Execution completes | Continue to verification | No |
| Execution blocked | Report blocked, reject | Yes |
| Verification passes | Push branch, `fs done` | Yes |
| Verification fails (fixable) | Fix and re-verify | No |
| Verification fails (not fixable) | Report blocked | Yes |
