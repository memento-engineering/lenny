name: testing-anti-patterns
description: Use when writing or changing tests, adding mocks, or tempted to add test-only methods to production code

# Testing Anti-Patterns

**Load this reference when:** writing or changing tests, adding mocks, or tempted to add test-only methods to production code.

## Overview

Tests must verify real behavior, not mock behavior. Mocks are a means to isolate, not the thing being tested.

**Core principle:** Test what the code does, not what the mocks do.

**Following strict TDD prevents these anti-patterns.**

## The Iron Laws

```
1. NEVER test mock behavior
2. NEVER add test-only methods to production classes
3. NEVER mock without understanding dependencies
```

## Anti-Pattern 1: Testing Mock Behavior

**The violation:**
```
# BAD: Testing that the mock exists
test "renders component":
  render(Page)
  assert element("mock-sidebar") exists   # Testing the mock, not the component!
```

**Why wrong:** You're verifying the mock works, not that the component works. Tells you nothing about real behavior.

**The fix:** Test real component or don't mock it. If you must mock for isolation, don't assert on the mock — test the real behavior with the mock present.

### Gate Function

```
BEFORE asserting on any mock element:
  Ask: "Am I testing real behavior or just mock existence?"
  IF testing mock existence: STOP — delete the assertion or unmock
```

## Anti-Pattern 2: Test-Only Methods in Production

**The violation:**
```
# BAD: destroy() only used in tests
class Session:
  def destroy():         # Looks like production API!
    cleanup_workspace()
    # ... only called in afterEach
```

**Why wrong:** Production class polluted with test-only code. Dangerous if accidentally called in production.

**The fix:** Move cleanup to test utilities, not the production class.

### Gate Function

```
BEFORE adding any method to production class:
  Ask: "Is this only used by tests?"
  IF yes: STOP — put it in test utilities instead
```

## Anti-Pattern 3: Mocking Without Understanding

**The violation:**
```
# BAD: Mock prevents side effect the test depends on
mock(Catalog.discover, returns: nothing)

add_item(config)
add_item(config)  # Should throw duplicate — but mock broke the detection!
```

**Why wrong:** Over-mocking "to be safe" breaks actual behavior the test depends on.

**The fix:** Understand dependencies first. Mock at the correct level — the slow/external part, not the behavior the test needs.

### Gate Function

```
BEFORE mocking any method:
  1. Ask: "What side effects does the real method have?"
  2. Ask: "Does this test depend on any of those side effects?"
  3. Ask: "Do I fully understand what this test needs?"

  IF depends on side effects: Mock at lower level, NOT the method test depends on
  IF unsure: Run test with real implementation FIRST, then add minimal mocking
```

## Anti-Pattern 4: Incomplete Mocks

**The violation:**
```
# BAD: Only fields you think you need
mock_response = { status: "success", data: { id: "123" } }
# Missing: metadata that downstream code uses
# Later: breaks when code accesses response.metadata.request_id
```

**Why wrong:** Partial mocks hide structural assumptions. Tests pass but integration fails.

**The fix:** Mirror the real data structure completely. If you're mocking an API response, include ALL fields the system might consume.

## Anti-Pattern 5: Integration Tests as Afterthought

**The violation:**
```
Implementation complete.
No tests written.
"Ready for testing."
```

**Why wrong:** Testing is part of implementation, not optional follow-up.

**The fix:** TDD cycle: write failing test → implement to pass → refactor → then claim complete.

## TDD Prevents These Anti-Patterns

1. **Write test first** — forces thinking about what you're actually testing
2. **Watch it fail** — confirms test tests real behavior, not mocks
3. **Minimal implementation** — no test-only methods creep in
4. **Real dependencies** — you see what the test actually needs before mocking

## Quick Reference

| Anti-Pattern | Fix |
|--------------|-----|
| Assert on mock elements | Test real component or unmock it |
| Test-only methods in production | Move to test utilities |
| Mock without understanding | Understand dependencies first, mock minimally |
| Incomplete mocks | Mirror real data structure completely |
| Tests as afterthought | TDD — tests first |
| Over-complex mocks | Consider integration tests |

## Red Flags

- Assertion checks for mock test IDs
- Methods only called in test files
- Mock setup is >50% of the test
- Test fails when you remove mock
- Can't explain why mock is needed
- Mocking "just to be safe"

## The Bottom Line

**Mocks are tools to isolate, not things to test.**

If you're testing mock behavior, you've gone wrong. Test real behavior or question why you're mocking at all.
