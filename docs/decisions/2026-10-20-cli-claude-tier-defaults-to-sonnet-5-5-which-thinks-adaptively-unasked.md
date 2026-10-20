---
status: accepted
date: 2026-10-20
decision-makers:
  - "Nico Spencer"
consulted:
  - "claude"
informed: []
register:
  spec: 1
  slug: cli-claude-tier-defaults-to-sonnet-5-5-which-thinks-adaptively-unasked
  surfaces:
    - "packages/leonard_cli/lib/src/provider_factory.dart"
    - "packages/leonard_agent/lib/src/provider/capabilities_lookup.dart"
    - "packages/leonard_agent/lib/src/provider/backend/model_backend.dart"
  obsoletes: []
  updates:
    - "claude-models-newer-than-4-6-run-without-thinking-until-adaptive-is-supported"
  obsoleted-by: null
  updated-by: []
  bead: lenny-e9y7g
  legacy-id: null
---

# CLI claude tier defaults to Sonnet 5.5, which thinks adaptively unasked

## Context and Problem Statement

`--model claude` defaulted to `claude-sonnet-4-6`. On the 2026-10-20 live tier
run, `claude-sonnet-5-5` finished the sample-app goal in 20 s for $0.26
against Sonnet 4.6's 35 s and $0.35. The earlier decision that day recorded
that Claude models newer than 4.6 "run without thinking", which made the
switch look like a trade of thinking for speed.

## Decision Outcome

* **`--model claude` defaults to `claude-sonnet-5-5`**, with vision advertised
  as it is for Sonnet 4.6 (the Models API lists image input for it). Ruled by
  Nico in chat, 2026-10-20.
* **Correction to the thinking decision, which stays in force:** the gate
  sends a newer model no thinking field, and a Claude 5 model given none
  thinks adaptively. A one-call `claude-sonnet-5-5` probe with no thinking
  field returned a thinking block and 170 thinking tokens. Only Opus 4.7 and
  4.8 run without thinking under the gate. The code is unchanged; its doc
  comments now say this.

### Consequences

* Good, because the default tier is faster and cheaper on the measured goal,
  and still thinks.
* Bad, because the Sonnet 5.5 default sends screenshots now, so its input
  token count per run will rise above the 2026-10-20 measurement, which ran
  with vision off.
