name: bead-format
description: Use when writing or validating bead structured fields — field storage rules, type-based conventions, size thresholds, epic vs work unit examples

# Bead Format — Specification Output

The standard bead structure produced by the specify skill and consumed by build and review.

## Structured Field Storage

Beads use **structured fields**, NOT a single markdown body. Each section lives in its designated field:

| Field | Contains | How to write |
|-------|----------|-------------|
| `description` | Problem context, background, what and why | `bd update <id> --description '...'` |
| `acceptance_criteria` | Testable success criteria (checkboxes) | `bd update <id> --acceptance '...'` |
| `design` | Implementation Plan + Validation Plan | `bd update <id> --design '...'` |
| `notes` | References, links, additional context | `bd update <id> --notes '...'` |

**Important:** The `description` field is for context ONLY. Never put `## Acceptance Criteria`, `## Implementation Plan`, or `## Validation Plan` in the description — the lint will reject it.

### acceptance_criteria field

```markdown
- [ ] Criterion 1
- [ ] Criterion 2
```

### design field

```markdown
## Implementation Plan
1. Step — `file/path.ext` description with concrete types
2. Step — `AnotherFile.ext` description

## Validation Plan
- Test type: what to verify
- Test type: what to verify
```

## Type-Based Conventions

### Epics — Plan Containers

Epics hold the full design for large features. They are **never dispatched** to builders.

- **design field:** Unlimited size. Contains full architecture, phased plans, code examples, and rationale.
- **acceptance_criteria:** High-level success criteria for the entire feature.
- **Children:** An epic is decomposed into child stories/tasks. Each child is a self-contained work unit.
- **Build:** Builders NEVER build epics. They exist for planning and tracking, not implementation.

Use an epic when:
- The plan exceeds 10 implementation steps
- The design field would substantially exceed 12KB
- Work spans multiple independent phases or files

### Stories / Tasks / Bugs — Work Units

Work units are self-contained, size-bounded, and buildable.

- **design field:** Aim for around 12KB. Advisory — the committee surfaces oversized scope via grades, not via a hard cap.
- **acceptance_criteria:** Aim for under 4KB. Advisory; exceeding is a hint to scope-check, not a gate.
- **Content style:** Concrete — actual code snippets, test commands, and expected output in every implementation step.
- **Self-contained:** A builder needs only `bd show <id>` to implement the bead. No external docs, no implicit context.

## Size Thresholds

| Limit | Default | Applies to | Enforcement |
|-------|---------|-----------|-------------|
| Design max | 12KB | stories, tasks, bugs | Advisory — committee grades scope |
| AC warn | 4KB | stories, tasks, bugs | Advisory — warning only |

**Epics are exempt from all size checks.**

12KB is roughly 3K tokens — enough for 8-10 detailed steps with code blocks. If you need more, the bead should be an epic with child tasks.

### Example: Epic vs Child Task

The same feature — "Add webhook retry with exponential backoff" — shown as an epic plan and one of its decomposed child tasks.

**Epic `proj-100` — design field (high-level plan, unlimited size):**

```markdown
## Implementation Plan

Phase 1 — Core retry engine
1. Create `RetryPolicy` struct — `lib/retry.ts` (maxAttempts, baseDelay, maxDelay, jitter)
2. Implement `executeWithRetry()` — `lib/retry.ts` generic async retry wrapper
3. Unit tests — `tests/retry.test.ts` cover success, exhaustion, jitter bounds

Phase 2 — Webhook integration
4. Wire `RetryPolicy` into `WebhookDispatcher` — `lib/webhooks.ts`
5. Add dead-letter queue for exhausted retries — `lib/dlq.ts`
6. Integration tests — `tests/webhooks.integration.test.ts`

Phase 3 — Observability
7. Add retry metrics (attempt count, final status) — `lib/metrics.ts`
8. Dashboard config — `grafana/webhook-retries.json`

## Validation Plan
- All phases have passing tests
- Retry respects backoff curve under load
- Dead-letter queue captures exhausted deliveries
```

**Child task `proj-101` (parent: `proj-100`) — design field (<=12KB):**

```markdown
## Implementation Plan

1. Create `RetryPolicy` type — `lib/retry.ts`
   ```ts
   export interface RetryPolicy {
     maxAttempts: number;  // default 5
     baseDelayMs: number;  // default 1000
     maxDelayMs: number;   // default 30000
     jitter: boolean;      // default true
   }
   ```

2. Implement `executeWithRetry()` — `lib/retry.ts`
   - Accept `fn: () => Promise<T>` and `policy: Partial<RetryPolicy>`
   - Compute delay: `min(baseDelay * 2^attempt, maxDelay)` +/- jitter
   - Throw after `maxAttempts` exhausted

3. Write tests — `tests/retry.test.ts`
   - Test: succeeds on first try -> no retry
   - Test: succeeds on 3rd attempt -> 2 retries, delays increase
   - Test: exhausts maxAttempts -> throws with last error
   - Test: jitter stays within +/-25% of computed delay
   ```bash
   npm test -- tests/retry.test.ts
   ```

## Validation Plan
- `npm test -- tests/retry.test.ts` passes (4 tests)
- `RetryPolicy` type is exported and importable
- No lint errors: `npm run lint -- lib/retry.ts tests/retry.test.ts`
```

**Key differences:**
- Epic has phases spanning multiple concerns; child task has concrete steps for one concern.
- Child task includes actual type definitions, test cases, and shell commands.
- Child task is self-contained — a builder implements it without reading the epic.

## Validation Rules

A bead is "ready" when:
1. `acceptance_criteria` field is non-empty and contains at least one checkbox item
2. `design` field contains `## Implementation Plan` with numbered steps
3. Every implementation step contains a backticked file path, type, or function name
4. `design` field contains `## Validation Plan` with at least one item
5. `description` does NOT contain duplicated section headers
6. `fs lint <id>` is clean (advisory; the committee weighs lint as one input among grades)

## Optional Sections

- `## Design` — architecture notes, key decisions, links to design docs
- `## Dependencies` — bead IDs this work depends on
