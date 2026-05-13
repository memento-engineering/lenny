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

### 4. Size Check (Advisory)

- Design field: aim for under **12KB** (~3K tokens, 8-10 detailed steps).
- Acceptance criteria field: aim for under **4KB**.

These are guidelines, not hard limits. The committee surfaces scope and concreteness issues via grades; if a spec is too large to be one bead, the committee will route it back to `draft` with a decompose hint. Don't auto-decompose on size — that's the committee's call.

### 5. Submit to the Committee

```bash
fs convene <id>
```

This transitions the bead from `in_spec` to `committee_review`. The committee (deliberators) then grades the spec on concreteness, decision density, and scope. Their verdict — not a CLI gate — decides whether the bead promotes to `ready`, returns to `in_spec` for revision, or returns to `draft` for decomposition.

### 6. Lint (Advisory)

```bash
fs lint <id>
```

Lint is advisory — it surfaces missing sections and structural gaps but does not block `fs convene`. Run it before submitting if you want a sanity check; the committee will weigh in regardless.

### 7. Hand Off

**Stop here.** Do NOT promote past `committee_review` yourself — the committee verdict drives that.

Hand off with: "Spec submitted to the committee. Review it with `bd show <id>`; the committee will grade and route."

Even if the human has already said "continue" or "keep going", still stop and hand off — those signals authorize the specify phase to finish, not to bypass the committee's review of what you produced.

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
- Write code (that's the forge skill).
- Promote past `committee_review` yourself — the committee verdict drives that.
- Write Implementation Plan or Validation Plan to the `description` field — they belong in `design`.
- Leave any section vague or incomplete.
- Auto-decompose on size — flag the human; the committee will route the bead back if it's truly too large.
