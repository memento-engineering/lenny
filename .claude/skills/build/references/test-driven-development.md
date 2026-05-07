name: test-driven-development
description: Use when implementing any feature or bugfix — before writing implementation code

# Test-Driven Development (TDD)

## Overview

Write the test first. Watch it fail. Write minimal code to pass.

**Core principle:** If you didn't watch the test fail, you don't know if it tests the right thing.

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Write code before the test? Delete it. Start over.

**No exceptions:**
- Don't keep it as "reference"
- Don't "adapt" it while writing tests
- Delete means delete

## When to Use

**Always:**
- New features
- Bug fixes
- Refactoring
- Behavior changes

**Exceptions (ask the human):**
- Throwaway prototypes
- Generated code
- Configuration files

## Red-Green-Refactor

### RED — Write Failing Test

Write one minimal test showing what should happen.

**Requirements:**
- One behavior per test
- Clear name describing the behavior
- Real code (no mocks unless unavoidable)

```
# Pseudocode — adapt to your language
test "rejects empty input":
  result = process(input: "")
  assert result.error == "input required"
```

### Verify RED — Watch It Fail

**MANDATORY. Never skip.**

```bash
# Run the test
<test command>
```

Confirm:
- Test fails (not errors)
- Failure message is expected
- Fails because feature is missing (not typos)

**Test passes immediately?** You're testing existing behavior. Fix the test.

**Test errors?** Fix the error, re-run until it fails correctly.

### GREEN — Minimal Code

Write the simplest code to pass the test. Nothing more.

```
# Pseudocode
function process(input):
  if not input or input.trim() == "":
    return { error: "input required" }
  # ...
```

Don't add features, refactor other code, or "improve" beyond the test.

### Verify GREEN — Watch It Pass

**MANDATORY.**

```bash
<test command>
```

Confirm:
- Test passes
- Other tests still pass
- Output is clean (no errors, warnings)

**Test fails?** Fix code, not test.

### REFACTOR — Clean Up

After green only:
- Remove duplication
- Improve names
- Extract helpers

Keep tests green. Don't add behavior.

### Repeat

Next failing test for next behavior.

## Why Order Matters

**"I'll write tests after to verify"** — Tests written after code pass immediately. Passing immediately proves nothing: might test the wrong thing, might test implementation not behavior, you never saw it catch the bug.

**"Already manually tested"** — Manual testing is ad-hoc. No record, can't re-run, easy to miss cases under pressure.

**"Deleting X hours of work is wasteful"** — Sunk cost fallacy. Working code without real tests is technical debt.

**"Tests after achieve the same goals"** — Tests-after answer "what does this do?" Tests-first answer "what should this do?" Tests-after are biased by your implementation.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Too simple to test" | Simple code breaks. Test takes 30 seconds. |
| "I'll test after" | Tests passing immediately prove nothing. |
| "Keep as reference, write tests first" | You'll adapt it. Delete means delete. |
| "Need to explore first" | Fine. Throw away exploration, start with TDD. |
| "Test hard = unclear design" | Listen to the test. Hard to test = hard to use. |
| "TDD will slow me down" | TDD is faster than debugging. |
| "Existing code has no tests" | You're improving it. Add tests for what you change. |

## Red Flags — STOP and Start Over

- Code before test
- Test passes immediately
- Can't explain why test failed
- Rationalizing "just this once"
- "Keep as reference" or "adapt existing code"

**All of these mean: Delete code. Start over with TDD.**

## Verification Checklist

Before marking work complete:

- [ ] Every new function/method has a test
- [ ] Watched each test fail before implementing
- [ ] Each test failed for expected reason (feature missing, not typo)
- [ ] Wrote minimal code to pass each test
- [ ] All tests pass
- [ ] Output clean (no errors, warnings)
- [ ] Tests use real code (mocks only if unavoidable)
- [ ] Edge cases and errors covered

## When Stuck

| Problem | Solution |
|---------|----------|
| Don't know how to test | Write the wished-for API. Write the assertion first. Ask the human. |
| Test too complicated | Design too complicated. Simplify the interface. |
| Must mock everything | Code too coupled. Use dependency injection. |
| Test setup huge | Extract helpers. Still complex? Simplify the design. |

## Debugging Integration

Bug found? Write a failing test reproducing it. Follow TDD cycle. The test proves the fix and prevents regression.

Never fix bugs without a test.

## Related

- **[testing-anti-patterns.md](testing-anti-patterns.md)** — common test mistakes to avoid
- **[verification-before-completion.md](verification-before-completion.md)** — verify before claiming done
