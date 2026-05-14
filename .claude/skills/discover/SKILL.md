---
name: discover
description: >
  The factory's front door. Dispatches on arg shape: a bare invocation or a
  topic/idea/question researches what the factory already knows (backlog +
  decision beads + code), then continues an existing bead or — on your yes —
  creates an ephemeral one and starts the design conversation. A bead-id with
  no prompt is advisory: it loads the bead and its graph and recommends the
  next lifecycle step. A bead-id followed by an instruction is directed: same
  context load, but it carries out the instruction (decompose, retype, close,
  fill in design, kick off specify).
  Use when the user says "let's build", "I have an idea", "plan this",
  "design this", "what's the state of <bead>", "what should I do with
  <bead>", or "have we already decided this".
---

# Discover

The front door. Figure out what the factory already knows, then either point the
human at the next step, carry out their instruction, or start a design conversation.

## Dispatch

Look at the first argument:

- **No arguments** (bare `/discover` or implicit trigger) → ask "What do you want to
  look into?" then treat the answer as a **topic** (see *Topic research*).
- **Arg 1 looks like a bead-id** — matches the project prefix form, e.g.
  `factoryskills-abc1` or `factoryskills-wisp-fai`. Confirm with `bd show <token>`
  before treating it as a bead ref. Then:
  - **nothing after it** → *Advisory* (read-only recommendation).
  - **a prompt after it** → *Directed* (carry out the instruction). Everything after
    the bead-id token is the prompt.
- **Arg 1 is anything else** (a phrase, an idea, a question — not a bead-id) → it's a
  **topic** (see *Topic research*).

The "what does the factory already know about this?" research layer runs in every shape
— only the anchor differs (a known bead vs. a topic). Only the directed shape *acts*;
advisory and topic-research do not, except topic-research may create a bead once the
human confirms.

## Topic research

For a bare invocation (after asking) or `/discover <topic / idea / question>`. "I have
an idea: XYZ" and "search for XYZ" are the same opening move — research first, create
only on confirmation.

1. **Search the backlog and the decision beads.** `bd search "<keywords>"` and
   `bd search "<keywords>" --status all` to catch closed/decided work. Search ADRs the
   same way (decision-type beads live in the same store).
2. **Read the hits.** `bd show <id>` for each promising match — status, design field,
   deps.
3. **Read the relevant code.** Enough to know whether this is genuinely new or a
   re-tread.
4. **Report one of two outcomes:**
   - **Already exists** — name the bead, its status, and what it covers. Ask: continue
     it? (If yes and it's a bead-id you can act on, that's the *Directed* or *Advisory*
     path — switch to it.)
   - **New** — name the adjacent beads and ADRs it intersects. Ask: want a bead for
     this?
5. **On the human's "yes" → create the bead, ephemeral by default:**
   ```bash
   fs discover "<title>" --type <feature|bug|task|epic> --ephemeral
   ```
   Then enter the discovery conversation (next section). Promote later, once the design
   is confirmed: `bd update <id> --persistent`. Do **not** create a bead before the
   human confirms — no junk beads for "oh, that already exists".

### Discovery conversation

Once you're on a typed bead (just created, or an existing one the human wants to keep
designing), load the shared discovery process in
[references/brainstorming.md](references/brainstorming.md) plus the type-specific
reference:

| Bead type | Reference | What's different |
|-----------|-----------|------------------|
| `epic` | [references/types/epic.md](references/types/epic.md) | Discovery + Phase 1b refinement (decomposition into stories) |
| `bug` | [references/types/bug.md](references/types/bug.md) | Repro-focused discovery, root cause investigation |
| `decision` | [references/types/decision.md](references/types/decision.md) | ADR exploration, tradeoff documentation |
| `feature`, `task`, `chore` | [references/types/default.md](references/types/default.md) | Standard discovery |

If the type isn't clear yet, start with the standard flow; retype when it emerges:
`bd update <id> --type epic`.

When the design is approved, write it into the bead so the specify worker has context
in isolation:

```bash
bd update <id> --description "One paragraph: what problem this solves and why it needs doing."
bd update <id> --design "Key decisions: approach chosen, constraints, what was ruled out and why, non-obvious implementation notes."
```

Then:
- If the human says "continue" / "specify it" / "keep going" → run `fs specify <id>`
  yourself and transition into the specify skill.
- Otherwise hand off: "Design approved. Run `fs specify <id>` when you're ready."

## Advisory

For `/discover <bead-id>` with no prompt. **Read-only — never dispatches** into specify,
forge, inspect, or route.

1. **Load the bead and its graph.** `bd show <id>` (status, grades, design field),
   `bd dep list <id>`, and `bd show` on the related beads and any ADRs it intersects.
2. **Read the relevant code/ADRs** for that bead.
3. **Recommend the next lifecycle step** — what it is, why, and the exact command the
   human should run (e.g. "this draft is thin — run `/discover <id> flesh out the
   design`", or "spec looks ready — `fs specify <id>`", or "graded and passing —
   `fs route <id>`").

Why this and not `fs status`? `fs status` shows where *everything* sits; `/discover
<id>` primes *this* conversation's context with the bead and its graph so the human can
act on it now.

**Relation to autonomous discovery (`factoryskills-rh2w`):** advisory mode only
*notices* that a thin draft needs a discovery pass and points at the command — it does
not perform the autonomous design pass itself, and it does not block on rh2w.

## Directed

For `/discover <bead-id> <prompt>`. Same context load as *Advisory* (steps 1–2 above),
but instead of recommending, **carry out the instruction.** The human instruction *is*
the authorization to act — decompose the epic, retype the bead, close it, fill in the
design field, run `fs specify`, whatever was asked. Directed = advisory + permission.

If carrying out the instruction lands you on a typed bead that needs design work, fall
through to the *Discovery conversation* section.

## Exit Criteria

Before handing off from a discovery conversation, verify:
- The human has **explicitly approved** the design.
- No open questions remain.
- You can state what we're building in one sentence.

## What You Don't Do Here

- Write acceptance criteria or implementation plans (that's the specify skill).
- Write code (that's the forge skill).
- Create a bead before the human confirms in topic research.
- Dispatch into specify/forge/inspect/route from *Advisory* mode — only *Directed* mode
  acts, and only because the human gave an instruction.
- Perform the autonomous design pass that `factoryskills-rh2w` owns — just notice and
  point.
- Run `fs specify` yourself unless the human signals they want to continue.
- Ask multiple questions at once — one at a time.

## Forward note (not in scope)

The status→next-action mapping in *Advisory* is prose here. It could later be extracted
into a small `fs next <id>` / `fs recommend <id>` helper so it isn't duplicated; that's a
separate bead, not part of this one. A pluggable extension system (custom search sources /
next-step resolvers) is likewise deferred — discover it separately.
