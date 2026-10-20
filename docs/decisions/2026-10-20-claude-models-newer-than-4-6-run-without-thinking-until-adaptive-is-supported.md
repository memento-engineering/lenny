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
  slug: claude-models-newer-than-4-6-run-without-thinking-until-adaptive-is-supported
  surfaces:
    - "packages/leonard_agent/lib/src/provider/backend/model_backend.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: lenny-e9y7g
  legacy-id: null
---

# Claude models newer than 4.6 run without thinking until adaptive is supported

## Context and Problem Statement

The live tier run on 2026-10-20 failed on its first call with
`claude-sonnet-5-5`: the model rejects `thinking.type: enabled`, and dartantic
3.4.2, its latest release, can send nothing else. Measured against every model
id on the key, Opus 4.7, Opus 4.8 and all Claude 5 models reject it; 4.6 and
older accept it. The Anthropic SDK beneath dartantic already supports adaptive
thinking, so the options were to switch thinking off, own the Anthropic call,
or wait for upstream.

## Decision Outcome

* **Thinking is off for Claude models newer than 4.6**, decided from the model
  id (an unrecognised id counts as newer). 4.6 and older keep budgeted
  thinking. `tool_choice` stays `auto` for both: the newer models reject a
  forced tool choice too (measured live).
* **Upstream gets an issue, filed as the project's contributing guide asks
  (csells/dartantic#119), and no PR.** A PR is worth writing only if we move
  to our own fork.
* **A spike (lenny-e9y7g) weighs replacing dartantic**, or building provider
  and harness interfaces in genesis for the providers and agent harnesses
  memento-engineering uses, against the cost of the workarounds.

Ruled by Nico in chat, 2026-10-20.

### Consequences

* Good, because the claude tier runs on current models in this release.
* Bad, because those runs reason without extended thinking until adaptive
  thinking is reachable.
