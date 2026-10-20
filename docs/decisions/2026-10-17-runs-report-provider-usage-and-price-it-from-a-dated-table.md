---
status: accepted
date: 2026-10-17
decision-makers:
  - "Nico Spencer"
consulted:
  - "claude"
informed: []
register:
  spec: 1
  slug: runs-report-provider-usage-and-price-it-from-a-dated-table
  surfaces:
    - "packages/leonard_agent/lib/src/provider/model_usage.dart"
    - "packages/leonard_agent/lib/src/loop_driver/run_usage.dart"
    - "packages/leonard_agent/lib/src/provider/backend/dartantic_model_provider.dart"
    - "packages/leonard_agent/lib/src/trajectory/records.dart"
    - "packages/leonard_cli/lib/src/run.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: lenny-pxt3
  legacy-id: null
---

# Runs report provider usage and price it from a dated table

## Context and Problem Statement

GitHub #178: sizing CI hardware for agent-driven test runs (owned Macs serving
a local MLX model versus a hosted provider billed per token) needs the token
count, model latency and cost of a real `leonard_cli --goal` run. Leonard
recorded none of it: `DartanticModelProvider` dropped the usage every backend
streams, the footer held only turn count and duration, and the README showed
`tokens_in` / `tokens_out` keys the code never wrote.

Four questions had more than one reasonable answer: how far to go on cache
tokens, where prices come from, whether to record throughput, and how to ship.

## Decision Outcome

* **Every model call is counted, retries and failures included.** A turn can
  spend a schema retry and up to three validator retries; each is billed, so
  the loop driver meters the provider rather than reading only the accepted
  decision. A call the provider reported nothing for is counted in
  `calls_without_usage`, never as zero tokens.
* **Input and output tokens now; cache tokens later.** dartantic 3.4's usage
  type has no cache fields and Leonard sets no Anthropic `cache_control`, so
  cache counts are omitted until measurable (lenny-ktyl) and prompt caching is
  its own change (lenny-0bcv).
* **Prices come from a dated built-in table, overridable.** List prices for
  the hosted models the tiers run, checked on the providers' pricing pages on
  the table's date, recorded in the footer as the price source. A flag or env
  override prices any model, local ones included. A local `swift-infer` model
  or an unlisted model reports `estimated_cost_usd: null` — unset, not zero.
* **Throughput is recorded.** Time to first token and output tokens per
  second, per call and per run, because for owned hardware speed is what is
  being bought and total latency conflates prompt processing with generation.
* **Ship on the dev rung first**, then promote after a real run on each tier.

Ruled by Nico in chat, 2026-10-17, taking the recommended option on each of
the four questions.

### Consequences

* Good, because a run's cost and speed come from the provider's own figures,
  in the trajectory and in a `--summary-json` file CI can collect.
* Bad, because the built-in prices go stale; the date in the footer's
  `price.source` says how stale, and the override covers the gap.
* Bad, because without cache tokens a cached Anthropic or OpenAI prompt is
  costed at full input price, so hosted cost reads high until lenny-ktyl.
