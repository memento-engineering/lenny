# Specify

Translate an approved design into a concrete, implementation-ready spec.

## Process

### 1. Load Context

```bash
bd show <id>
```

Read the approved design from the discovery phase. Understand what was agreed before writing the spec.

### 2. Write Acceptance Criteria

```bash
bd update <id> --acceptance
```

Rules:
- One testable criterion per checkbox: `- [ ] criterion`
- Every criterion must be verifiable — no vague statements ("works well", "is fast").
- If you can't write a test for it, it's not a criterion.

### 3. Write Implementation Plan + Validation Plan

Both plans go in the `design` field, **never the description**. Use the `--design` flag — `--description` is for problem context only and `fs lint` will reject plans placed there.

Write both sections in a single `bd update` call using a heredoc:

```bash
bd update <id> --design "$(cat <<'EOF'
## Implementation Plan

1. Step — `file/path.ext` short description
   ```go
   // concrete code, not pseudo-code
   ```
   Test: `go test -run TestX ./pkg/...` → expect PASS
   Commit: `feat(pkg): short description`

2. Step — `other/file.ext` short description
   ...

## Touches

**Files:**
- `path/to/file.ext` — created or modified

**Symbols added/exposed:**
- `package.SymbolName` — type/function/field, brief description

## Validation Plan

- [ ] Acceptance criterion 1 → `exact command` → expected output
- [ ] Acceptance criterion 2 → `exact command` → expected output
EOF
)"
```

See [writing-plans.md](writing-plans.md) for the full step format,
before/after examples, and granularity guidance.

Every implementation step must include:
- **Code block** — the actual code, not pseudo-code.
- **File path** — exact, backticked, from repo root.
- **Test command** — exact shell command + expected output.
- **Commit message** — conventional commit format.

Step granularity: one step = 2-5 minutes of builder work.

Validation plan rules:
- Map each validation item back to an acceptance criterion.
- Include exact test commands and expected results.
- Cover the full acceptance criteria — no gaps.

**No placeholders.** These are spec failures — never write them:
- "TBD", "TODO", "implement later"
- "Add appropriate error handling"
- "Similar to step N" (repeat the content)
- Steps that describe what to do without showing how

#### Sibling Cross-Check

Before drafting the implementation plan, check whether this bead is part of an epic:

```bash
bd dep list <id> --json -t parent-child   # find the parent epic, if any
```

If a parent exists, list every sibling (other children of the same epic) and read their `## Touches` sections from `bd show <sibling-id> --json` (`.design`). Then ensure every public symbol your plan references that is **not** in this bead's own diff is either (a) added by a sibling that this bead has an explicit dependency on, or (b) outside the epic entirely.

If your plan references a sibling-exposed symbol without a declared dep:
- Add the dep: `bd dep add <this-id> <sibling-id>`, OR
- Restructure so this bead is self-contained.

Don't proceed until one is true. Implicit cross-bead state is the failure mode of factoryskills-9ef.

### 4. Size Check

- Design field: **12KB max** (~3K tokens, 8-10 detailed steps).
- Acceptance criteria field: **4KB max**.

If either limit is exceeded, the work is too large for a single bead. Tell the human:

> "This spec exceeds size limits. It needs to become an epic and be decomposed. Go back to the discover skill for decomposition."

### 5. Gate the Transition

```bash
fs specify <id>
```

This validates that acceptance criteria and design fields are populated (including `## Implementation Plan` and `## Validation Plan` sections in the design), then transitions the bead from draft to planned. If it fails, the fields need more work.

### 6. Lint

```bash
fs lint <id>
```

Must pass. Fix any issues before handing off.

### 7. Hand Off

**Stop here.** Do NOT run `fs ready <id>` yourself — that is the human's review gate and skipping it defeats the point of having a spec review step.

Hand off with: "Spec complete. Review it with `bd show <id>`, then promote with `fs ready <id>` when satisfied."

Even if the human has already said "continue" or "keep going", still stop and hand off — those signals authorize the specify phase to finish, not to bypass the review of what you produced.

## Bead Field Format

See [bead-format.md](bead-format.md) for structured field storage rules,
type-based conventions (epics vs work units), size thresholds, and worked examples.

## Craft Methodology References

Load on-demand during specification:

| When | Load |
|------|------|
| Writing implementation steps or unsure about step format | [writing-plans.md](writing-plans.md) |
| Writing to bead fields or checking type conventions | [bead-format.md](bead-format.md) |

## What You Don't Do Here

- Redesign the approach (that was the discover skill).
- Write code (that's the build skill).
- Run `fs ready` — ever. That is the human's review gate.
- Write Implementation Plan or Validation Plan to the `description` field — they belong in `design`.
- Leave any section vague or incomplete.
- Skip the size check.
