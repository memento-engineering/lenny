name: brainstorming
description: Use during Phase 1 discovery — collaborative questioning, approach exploration, and incremental design presentation

# Brainstorming — Phase 1: Discovery

Explore ideas through collaborative questioning. Understand what we're building before specifying how.

## Process

1. **Explore project context** — check files, docs, recent commits
2. **Check existing work** — `fs status` to see if related beads exist
3. **Ask clarifying questions** — one at a time, understand purpose/constraints/success criteria
4. **Propose 2-3 approaches** — with trade-offs and your recommendation
5. **Present design** — section by section, get user approval after each

## Questioning Rules

- **One question at a time.** Don't overwhelm with multiple questions.
- **Multiple choice preferred.** Easier to answer than open-ended when possible.
- **Open-ended is fine** when the design space is genuinely wide.
- **Follow up.** If an answer raises new questions, explore before moving on.

## Exploring Approaches

When you understand the problem:

1. Propose 2-3 different approaches with trade-offs
2. Lead with your recommended option and explain why
3. Present options conversationally — not a formal comparison matrix
4. Be opinionated. "I'd go with option A because..." is better than "all options are valid"

## Presenting the Design

Once you believe you understand what you're building:

1. Present the design section by section
2. Scale each section to its complexity — a sentence if straightforward, a paragraph if nuanced
3. Ask after each section: "Does this look right so far?"
4. Cover: architecture, components, data flow, error handling, testing approach
5. Be ready to go back and revise if something doesn't land

## Anti-Patterns

### "This Is Too Simple To Need Discovery"

Every project goes through discovery. A config change, a single-function utility, a todo list — all of them. "Simple" projects are where unexamined assumptions cause the most wasted work. The discovery can be brief (one or two questions), but it must happen.

### Premature Specification

Don't jump to writing acceptance criteria during discovery. The goal here is understanding, not documenting. Specification is the specify skill's job.

### Design By Committee

You're a collaborator, not a stenographer. Push back on ideas you think are wrong. Propose alternatives. Have opinions. The user wants a thinking partner, not a yes-machine.

## Exit Criteria

Discovery is complete when:
- You can articulate what we're building in one sentence
- The user has approved the design (explicitly, not assumed)
- No open questions remain that would block specification

After discovery, follow the routing defined in the type-specific reference that
dispatched here. Each type defines its own exit path.

## Key Principles

- **YAGNI ruthlessly** — remove unnecessary features from all designs
- **Incremental validation** — present design, get approval, then move on
- **Be flexible** — go back and clarify when something doesn't land
- **Explore before committing** — always propose alternatives before settling
