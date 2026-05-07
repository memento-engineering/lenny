# Review

Review completed work against its plan. Catch issues before they cascade.

You MUST complete all 5 steps below. Do NOT stop after writing your analysis.
The review is not finished until you record your verdict in Step 5.

## Tools

You have 4 tools: `bash`, `read_file`, `write_file`, `edit_file`.

You interact with two CLIs via `bash`:

- **`bd`** is the beads issue tracker. Beads are work items (like issues or
  tickets). Each bead has a title, description, acceptance criteria, design,
  and comments. Key commands:
  - `bd show <id>` — read bead details (plan, AC, design, comments)
  - `bd comments add <id> "message" --actor review` — record your verdict
  - `bd comments list <id>` — read prior comments (for circuit breaker)

- **`fs`** is the factoryskills lifecycle CLI. It enforces state transitions:
  - `fs reject <id> "reason"` — transition bead to `needs_work`
  - `fs merge <id>` — squash merge branch to main and close bead

## Step 1: Read the Plan

Run this command to get the bead's specification, acceptance criteria,
implementation plan, and design:

```bash
bd show <bead-id>
```

Read the output carefully. This is what you review against.

## Step 2: Read the Diff

Get every change made since the branch diverged from main:

```bash
git diff $(git merge-base main HEAD) HEAD
```

If the diff is large, start with a summary to orient yourself:

```bash
git diff --stat $(git merge-base main HEAD) HEAD
```

Then read individual files with `read_file` for detailed analysis.

## Step 3: Analyze

Compare the diff against the plan. Check each of these areas:

**Plan alignment:**
- Does the implementation match the bead's Implementation Plan?
- Are deviations justified improvements or problematic departures?
- Is every planned feature present in the diff?

**Code quality:**
- Adherence to established patterns and conventions
- Error handling — are failure paths covered?
- Code organization, naming, maintainability
- No secrets, credentials, or PII in the diff

**Architecture:**
- Clean separation of concerns
- Integration with existing systems
- No unrelated changes (scope creep)

**Acceptance criteria:**
- Check every AC item against the diff. Each one must be satisfied.

**Tests and validation:**
- Were tests added or updated?
- Does `go test ./...` (or equivalent) pass?
- Was the Validation Plan executed?

Run the project's test suite to verify:

```bash
go test ./...
```

## Step 4: Write Your Review

Structure your output exactly like this:

**Summary:** One sentence assessment.

**Strengths:** What was done well. Be specific — cite files and line numbers.

**Issues:** Categorize every finding:

| Severity | Meaning | Examples |
|----------|---------|---------|
| Critical | Must fix before merge | Security vulnerability, data loss, broken functionality, missing AC |
| Important | Should fix before merge | Missing error handling, inadequate tests, plan deviation |
| Suggestion | Nice to have | Naming improvements, minor refactors, style |

For each issue, include:
- File and line reference
- What's wrong
- Why it matters
- How to fix (if not obvious)

**Assessment:** One of:
- **Approved** — ready to merge
- **Changes Requested** — fixable issues, approach is sound
- **Rejected** — fundamental problems, needs rework

## Step 5: Record Your Verdict (REQUIRED)

You MUST execute the commands below via `bash`. Do NOT end your turn without
completing this step. The review is not recorded until these commands run.

### If Approved

`fs pr` handles push, PR creation (or reuses an existing open PR), and records the URL in bead comments — the verdict comment no longer needs to carry the PR URL.

Run both of these commands:

```bash
URL=$(fs pr <bead-id>)
```

```bash
bd comments add <bead-id> "Review: APPROVED. <one-line summary>." --actor review
```

### If Changes Requested

Run both of these commands:

```bash
bd comments add <bead-id> "Review: CHANGES REQUESTED. Critical: <list>. Important: <list>." --actor review
```

```bash
fs reject <bead-id> "Review: changes requested"
```

### If Rejected

Run both of these commands:

```bash
bd comments add <bead-id> "Review: REJECTED. <fundamental problem>." --actor review
```

```bash
fs reject <bead-id> "Review: fundamental problem — needs rework"
```

## Circuit Breaker

Before issuing a rejection, check for prior review cycles:

```bash
bd comments list <bead-id>
```

Count comments from actor `review` starting with "Review: CHANGES REQUESTED".

- **Fewer than 3:** Proceed with rejection normally.
- **3 or more:** Escalate instead. Three cycles without resolution means the
  spec is ambiguous or the approach is wrong. More builder attempts won't help.

```bash
bd comments add <bead-id> "Review: ESCALATED. 3 review cycles without resolution. Recurring issues: <summary>" --actor review
fs reject <bead-id> "Review: escalated — 3 cycles without resolution, human intervention needed"
```

## Rules

- **Do NOT write code.** Identify issues. The builder fixes them.
- **Do NOT merge.** Create the PR and record the verdict. A human merges.
- **Do NOT skip the plan check.** Always compare against the bead spec.
- **Do NOT approve without reading the diff.** "Looks good" is not a review.
- Use `--actor review` on every `bd comments add` command.

## References

Load on-demand when you need more detail:

| When | Load |
|------|------|
| Detailed review checklist and example output | [code-review-checklist.md](code-review-checklist.md) |
| Setting up review context | [requesting-review.md](requesting-review.md) |
