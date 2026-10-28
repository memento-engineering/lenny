---
status: accepted
date: 2026-10-28
decision-makers: ["nico"]
consulted: ["claude"]
informed: []
register:
  spec: 1
  slug: anthropic-prompt-caching-is-set-on-the-wire-by-a-leonard-client
  surfaces:
    - "packages/leonard_agent/lib/src/provider/backend/dartantic_model_provider.dart"
    - "packages/leonard_agent/lib/src/provider/backend/anthropic_prompt_cache_client.dart"
  obsoletes: []
  updates:
    - adr-0003-model-backend-on-dartantic
  obsoleted-by: null
  updated-by: []
  bead: lenny-0bcv
  legacy-id: null
---
# Anthropic prompt caching is set on the wire by a Leonard client

## Context

Every claude-tier turn resends the whole conversation, system prompt included,
and pays the full input price for all of it, although everything but the
newest turn was already sent on the turn before. Anthropic can serve that
repeated prefix from its prompt cache, but only up to blocks the request marks
as cache breakpoints.

Leonard drives Anthropic through dartantic (ADR 0003). dartantic 3.4's
Anthropic model renders the system prompt as one string and offers no cache
control, so nothing Leonard passes it can mark a breakpoint.

## Decision

Leonard caches the Anthropic prompt by rewriting each outgoing messages request
in an http client it owns, not by forking or patching dartantic. The rewrite
moves into dartantic's options once dartantic exposes cache control, and that
change obsoletes this entry.

The breakpoints are the end of the system prompt and the end of the
conversation the model has already answered. The newest user turn, the tool
definitions and thinking blocks are never marked, and a request never carries
more than Anthropic's four breakpoints, counting any it already holds.

The rewriting client retries nothing and closes nothing, so the loop driver
still owns retry. This amends ADR 0003's "the Anthropic path uses the supplied
client directly" only in that the supplied client is now reached through the
rewriting client.

A provider given no client opens one for its Anthropic turns and closes it when
disposed. A provider given a client never closes it.

Only the Anthropic backend is rewritten. The swift-infer and OpenAI wires are
unchanged.

The exact marking rules are in the client's doc comment and pinned by its
test.

## Considered alternatives

- Fork dartantic's Anthropic mappers. Rejected: a fork to maintain across
  dartantic releases.
- Require every factory to pass a client. Rejected: the CLI and devtools
  factories pass none, and the governor kept them out of scope.
- Mark the newest user turn too. Rejected by the governor's ruling: it changes
  every turn, so a breakpoint there is never read back.

## Consequences

Cached input is still priced at the full rate in run reports until cache tokens
are surfaced (lenny-ktyl), as
`runs-report-provider-usage-and-price-it-from-a-dated-table` already records.
Prompts below Anthropic's minimum cacheable length get no cache read.

The CLI never disposes a direct dartantic provider, so the client it opens
lives until the process exits, which is no change from today's per-turn
clients.

## Falsified by

A live claude-tier run, once cache tokens are reported, whose second and later
turns show no cache reads although the prompt is above the minimum length; or
Anthropic rejecting a rewritten request.
