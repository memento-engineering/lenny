name: systematic-debugging
description: Use when encountering any bug, test failure, or unexpected behavior — before proposing fixes

# Systematic Debugging

## Overview

Random fixes waste time and create new bugs. Quick patches mask underlying issues.

**Core principle:** ALWAYS find root cause before attempting fixes. Symptom fixes are failure.

## The Iron Law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

If you haven't completed Phase 1, you cannot propose fixes.

## When to Use

Use for ANY technical issue:
- Test failures
- Bugs in production
- Unexpected behavior
- Performance problems
- Build failures
- Integration issues

**Use this ESPECIALLY when:**
- Under time pressure (emergencies make guessing tempting)
- "Just one quick fix" seems obvious
- You've already tried multiple fixes
- You don't fully understand the issue

**Don't skip when:**
- Issue seems simple (simple bugs have root causes too)
- You're in a hurry (systematic is faster than thrashing)

## The Four Phases

You MUST complete each phase before proceeding to the next.

### Phase 1: Root Cause Investigation

**BEFORE attempting ANY fix:**

1. **Read Error Messages Carefully**
   - Don't skip past errors or warnings
   - Read stack traces completely
   - Note line numbers, file paths, error codes

2. **Reproduce Consistently**
   - Can you trigger it reliably?
   - What are the exact steps?
   - If not reproducible, gather more data — don't guess

3. **Check Recent Changes**
   - What changed that could cause this?
   - Git diff, recent commits
   - New dependencies, config changes

4. **Gather Evidence in Multi-Component Systems**

   When system has multiple components:
   ```
   For EACH component boundary:
     - Log what data enters component
     - Log what data exits component
     - Verify environment/config propagation
     - Check state at each layer

   Run once to gather evidence showing WHERE it breaks
   THEN analyze evidence to identify failing component
   THEN investigate that specific component
   ```

5. **Trace Data Flow**

   See [root-cause-tracing.md](root-cause-tracing.md) for the complete backward tracing technique.

   Quick version:
   - Where does the bad value originate?
   - What called this with the bad value?
   - Keep tracing up until you find the source
   - Fix at source, not at symptom

### Phase 2: Pattern Analysis

1. **Find Working Examples** — locate similar working code in same codebase
2. **Compare Against References** — read reference implementation completely, don't skim
3. **Identify Differences** — list every difference, however small
4. **Understand Dependencies** — what components, settings, config does this need?

### Phase 3: Hypothesis and Testing

1. **Form Single Hypothesis** — state clearly: "I think X is the root cause because Y"
2. **Test Minimally** — make the SMALLEST possible change. One variable at a time.
3. **Verify Before Continuing** — did it work? If not, form NEW hypothesis. Don't pile on more fixes.

### Phase 4: Implementation

1. **Create Failing Test Case** — simplest possible reproduction, automated if possible
2. **Implement Single Fix** — address the root cause. ONE change. No "while I'm here" improvements.
3. **Verify Fix** — test passes? No other tests broken? Issue actually resolved?
4. **If Fix Doesn't Work:**
   - Count: how many fixes have you tried?
   - If < 3: return to Phase 1 with new information
   - **If >= 3: STOP and question the architecture**
   - DON'T attempt fix #4 without discussion

5. **If 3+ Fixes Failed: Question Architecture**

   Pattern indicating architectural problem:
   - Each fix reveals new shared state/coupling
   - Fixes require massive refactoring
   - Each fix creates new symptoms elsewhere

   **STOP and discuss with the human before attempting more fixes.**

## Red Flags — STOP and Follow Process

If you catch yourself thinking:
- "Quick fix for now, investigate later"
- "Just try changing X and see if it works"
- "Add multiple changes, run tests"
- "Skip the test, I'll manually verify"
- "It's probably X, let me fix that"
- "I don't fully understand but this might work"
- "One more fix attempt" (when already tried 2+)

**ALL of these mean: STOP. Return to Phase 1.**

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Issue is simple, don't need process" | Simple issues have root causes too. Process is fast for simple bugs. |
| "Emergency, no time for process" | Systematic debugging is FASTER than guess-and-check thrashing. |
| "Just try this first, then investigate" | First fix sets the pattern. Do it right from the start. |
| "I'll write test after confirming fix works" | Untested fixes don't stick. Test first proves it. |
| "Multiple fixes at once saves time" | Can't isolate what worked. Causes new bugs. |
| "I see the problem, let me fix it" | Seeing symptoms ≠ understanding root cause. |
| "One more fix attempt" (after 2+ failures) | 3+ failures = architectural problem. Question pattern, don't fix again. |

## Supporting Techniques

- **[root-cause-tracing.md](root-cause-tracing.md)** — trace bugs backward through call stack
- **[defense-in-depth.md](defense-in-depth.md)** — add validation at multiple layers after finding root cause
- **[condition-based-waiting.md](condition-based-waiting.md)** — replace arbitrary timeouts with condition polling
- **[test-driven-development.md](test-driven-development.md)** — for creating failing test case (Phase 4)
- **[verification-before-completion.md](verification-before-completion.md)** — verify fix worked before claiming success
