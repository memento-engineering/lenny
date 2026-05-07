name: condition-based-waiting
description: Use when tests have arbitrary delays or are flaky — replace timeouts with condition-based polling

# Condition-Based Waiting

## Overview

Flaky tests often guess at timing with arbitrary delays. This creates race conditions where tests pass on fast machines but fail under load or in CI.

**Core principle:** Wait for the actual condition you care about, not a guess about how long it takes.

## When to Use

- Tests have arbitrary delays (sleep, setTimeout, time.sleep)
- Tests are flaky (pass sometimes, fail under load)
- Tests timeout when run in parallel
- Waiting for async operations to complete

**Don't use when:**
- Testing actual timing behavior (debounce, throttle intervals)
- In that case, document WHY the timeout is needed

## Core Pattern

```
# BEFORE: Guessing at timing
sleep(50ms)
result = get_result()
assert result is not None

# AFTER: Waiting for condition
wait_for(condition: get_result() is not None)
result = get_result()
assert result is not None
```

## Quick Patterns

| Scenario | Pattern |
|----------|---------|
| Wait for event | `wait_for(events.find(type == "DONE"))` |
| Wait for state | `wait_for(machine.state == "ready")` |
| Wait for count | `wait_for(items.length >= 5)` |
| Wait for file | `wait_for(file_exists(path))` |
| Complex condition | `wait_for(obj.ready AND obj.value > 10)` |

## Implementation

Generic polling function (adapt to your language):

```
function wait_for(condition, description, timeout = 5000ms):
  start = now()

  loop:
    result = condition()
    if result:
      return result

    if elapsed(start) > timeout:
      raise "Timeout waiting for {description} after {timeout}ms"

    sleep(10ms)  # Poll every 10ms
```

**Always include:**
- Timeout with clear error message
- Description for debugging
- Reasonable poll interval (10ms is usually fine)

## Common Mistakes

- **Polling too fast** (every 1ms) — wastes CPU
- **No timeout** — loops forever if condition never met
- **Stale data** — caching state before the loop instead of checking fresh each iteration
- **No description** — timeout error gives no context

## When Arbitrary Timeout IS Correct

```
# First: wait for the triggering condition
wait_for(process_started)

# Then: wait for timed behavior with DOCUMENTED reason
sleep(200ms)  # Process ticks every 100ms — need 2 ticks for output
```

**Requirements:**
1. First wait for the triggering condition
2. Timeout based on known timing (not guessing)
3. Comment explaining WHY
