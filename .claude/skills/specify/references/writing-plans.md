name: writing-plans
description: Use when writing implementation plans — step format, before/after examples, size awareness, granularity guidance, no-placeholder rules

# Writing Plans — Phase 2: Specification

Translate an approved design into a structured, implementation-ready bead.

## Output

The bead must have three sections written to structured fields:

### Acceptance Criteria

Testable conditions that define "done." Each criterion is a checkbox.

```markdown
- [ ] Server starts and accepts MQTT connections on configured port
- [ ] QoS 0 publish/subscribe works end-to-end
- [ ] Malformed packets return appropriate MQTT error codes
```

**Rules:**
- Each criterion is independently testable
- No vague criteria ("works well", "is fast")
- Include error cases and edge cases
- Order from most to least critical

### Implementation Plan

Ordered steps that a developer with zero codebase context can follow.
Every step must include ALL four elements: code block, file path, test command, and commit.

### Validation Plan

How to verify the implementation satisfies the acceptance criteria.

```markdown
## Validation Plan
- Unit tests: codec round-trip, broker subscribe/publish/unsubscribe
- Integration test: full client connect -> subscribe -> publish -> receive flow
- Error test: malformed packet handling, connection limit enforcement
- Manual: start server, connect with mosquitto_pub/sub, verify messages flow
```

**Rules:**
- Map back to acceptance criteria — every criterion has a validation method
- Prefer automated tests over manual verification
- Include specific test names or descriptions
- Note any setup requirements (test fixtures, external tools)

### Touches

Lists what this bead modifies and what it exposes for siblings to consume. **Required for non-epic beads** (lint warns when missing).

```markdown
## Touches

**Files:**
- `lib/retry.ts` — created
- `lib/webhooks.ts` — modified (~line 80, integrate retry)

**Symbols added/exposed:**
- `lib/retry.ts:RetryPolicy` — interface
- `lib/retry.ts:executeWithRetry()` — generic async retry wrapper
```

**Rules:**
- List every file the implementation creates or modifies. Include line hints if helpful.
- List public types, functions, fields, and methods this bead adds. Skip internals not referenced by siblings.
- Other beads in the same epic read this section to cross-check shared state at spec time (see specify process's "Sibling Cross-Check"). Without it, sibling beads can reference your symbols with no declared dep — see factoryskills-9ef.

## Step Format

Every implementation step must include ALL of these elements. No exceptions.

**N. [Action] — `exact/file/path.ext`**

What to do and why (one sentence of context). Include line hints when modifying existing files.

```language
// The actual code to write — not a description of it
func example() -> Bool {
    return true
}
```

**Test:**
```bash
go test ./path/to/package -run TestExample -v
```
Expected: PASS — "example returns true"

**Commit:**
```bash
git add exact/file/path.ext
git commit -m "feat(scope): add example function"
```

### What Makes a Good Step

- **Code block:** The literal code to write or change. Show the full function, not a summary.
  If modifying existing code, show the before and after, or specify the insertion point with line hints.
- **File path:** Exact path from repo root, backticked. For modifications, include a line hint:
  `src/broker/handler.go` (~line 42, after `func Connect()`)
- **Test command:** The exact command to run and what the output should look like.
  Not "run the tests" — the specific test file, flag, and expected result.
- **Commit message:** Conventional commit format. One commit per logical unit.

## No Placeholders

Every step must contain the actual content. These are spec failures — never write them:

- **"TBD"**, **"TODO"**, **"implement later"**, **"fill in details"**
- **"Add appropriate error handling"** — show the actual error handling code
- **"Add validation"** — show the validation logic with conditions
- **"Handle edge cases"** — name each edge case and show the code for it
- **"Write tests for the above"** — show the test code with assertions
- **"Similar to Step N"** — repeat the code; the builder may read steps out of order
- **Steps that describe what to do without showing the code** — if there's no code block, the step is incomplete
- **"Update as needed"** / **"adjust accordingly"** — specify exactly what changes

**The test:** If a builder reading this step would need to make any decisions about
what code to write, the step is a placeholder. The plan should eliminate all ambiguity.

## Size Awareness

Beads have a design field size limit (default: 12KB for non-epic types).

**While writing the plan, monitor your step count:**

| Steps | Assessment | Action |
|-------|-----------|--------|
| 3-5   | Typical task | You're on track |
| 6-8   | Getting large | Verify each step is truly atomic (2-5 min) |
| 9-10  | At the boundary | Consider splitting into two beads |
| 10+   | Too large | Stop — create an epic and decompose into children |

**If the plan exceeds the threshold during writing:**

1. Stop writing steps in the current bead
2. Tell the human: "This spec exceeds size limits. It needs to become an epic and be decomposed. Go back to the discover skill for decomposition."

**Do NOT decompose inline.** Decomposition is a discovery activity — it requires
understanding scope boundaries, identifying seams, and wiring dependencies.
That's the discover skill's job, not the specify skill's.

## Step Granularity

Each step is one action a builder can complete in 2-5 minutes:

- "Write the failing test for X" — one step
- "Run the test to verify it fails" — one step (can combine with the previous if trivial)
- "Implement the minimal code to pass" — one step
- "Run tests and verify green" — one step
- "Commit" — fold into the implementation step's commit block

**Scale the plan to the work:**

- **Small bug fix** (1-2 hours): 3-5 steps with a TDD cycle
- **Task** (half day): 5-8 steps, inline in bead design field
- **Feature** (full day): 8-10 steps max — if more, epic + children

**Atomic means atomic:** If a step says "implement the parser and write tests for it,"
that's two steps. Split it. The builder should never have to decide where one
unit of work ends and the next begins.

## Before vs After

The same work, written two ways:

### Bad: Summary style

```markdown
## Implementation Plan
1. Add size threshold check to lint script — `scripts/lint-bead.sh`
2. Update tests for the new check
3. Update documentation
```

### Good: Concrete style

```markdown
## Implementation Plan

1. Add size threshold check after existing validations — `internal/lint/lint.go`

   After the validation plan check (~line 60), add:

   ```go
   // Size enforcement (non-epic only)
   if bead.Type != "epic" {
       if len(bead.Design) > 12288 {
           errors = append(errors, fmt.Sprintf(
               "design field is %dB (limit: 12288B)", len(bead.Design)))
       }
   }
   ```

   **Test:**
   ```bash
   go test ./internal/lint/ -run TestDesignSizeLimit -v
   ```
   Expected: PASS — "design field exceeds limit"

   **Commit:**
   ```bash
   git add internal/lint/lint.go
   git commit -m "feat(lint): add design field size check"
   ```

2. Add test case for size validation — `internal/lint/lint_test.go`

   Add a new test function:

   ```go
   func TestDesignSizeLimit(t *testing.T) {
       bead := &beads.Bead{
           Type:   "task",
           Design: strings.Repeat("x", 15000),
       }
       errors := Validate(bead)
       if len(errors) == 0 {
           t.Fatal("expected size limit error")
       }
   }
   ```

   **Test:**
   ```bash
   go test ./internal/lint/ -run TestDesignSizeLimit -v
   ```
   Expected: PASS

   **Commit:**
   ```bash
   git add internal/lint/lint_test.go
   git commit -m "test(lint): add design size threshold test"
   ```
```

**What changed:** The summary style tells the builder *what* to do. The concrete style
shows the builder *exactly* what to type. No decisions required. No ambiguity.

## Saving the Plan

Plans go into **structured bead fields**, NOT the description body. The `description`
is for context/background only — never put Acceptance Criteria, Implementation Plan,
or Validation Plan there.

1. Write acceptance criteria:
   ```bash
   bd update <id> --acceptance '- [ ] Criterion one
   - [ ] Criterion two'
   ```

2. Write Implementation Plan + Validation Plan to the design field:
   ```bash
   bd update <id> --design '## Implementation Plan
   1. Step — `file/path.ext`
      <code block, test, commit as above>

   ## Validation Plan
   - Test X: `command` -> expected output
   - Test Y: `command` -> expected output'
   ```

3. **Run lint — MUST pass before marking ready:**
   ```bash
   fs lint <id>
   ```

## Quality Gate — MANDATORY

**Do NOT hand off until ALL checks pass.** Run `fs lint <id>` to verify programmatically.

The lint enforces:
- [ ] `acceptance_criteria` field is populated (not in description)
- [ ] At least one checkbox item in acceptance criteria
- [ ] `design` field contains `## Implementation Plan` with numbered steps
- [ ] Every numbered step contains a backticked file path, type, or function name
- [ ] `design` field contains `## Validation Plan` with at least one item
- [ ] `description` does NOT contain duplicated section headers

Additionally, verify manually:
- [ ] Every acceptance criterion is testable (not vague)
- [ ] Implementation steps are ordered by dependency
- [ ] Validation plan covers all acceptance criteria
- [ ] No step depends on a later step
- [ ] Plan is self-contained — a developer with zero context can follow it
- [ ] Every step has all four elements: code block, file path, test command, commit message
- [ ] No placeholders or vague instructions (see "No Placeholders" above)
