# leonard_agent

Web-compatible harness library for Leonard. This
package MUST NOT import `dart:io` (enforced by
`tool/check_no_dart_io.sh`); concrete sinks and frontends live in sibling
packages (CLI, DevTools extension).

## Trajectory format (JSONL)

The harness writes one trajectory per session as newline-delimited JSON
(JSONL). The `TrajectoryWriter` (in `lib/src/trajectory/writer.dart`)
serializes typed records via a `TrajectorySink` and flushes after every
record, so a crashed session preserves progress through the last fully
written record (PRD §14).

**Ordering:** exactly one `header` on line 1, zero or more `turn` and
`extension_disabled` records interleaved in execution order, exactly one
`footer` on the last line. The writer flushes after every record.

**Size budget:** sessions are expected to stay under 50 MB / 30 minutes
(PRD §23). Readers should stream rather than slurp.

Each record is a JSON object with a `type` discriminator and snake_case
keys.

### `header`

Session metadata: goal, AGENTS.md hash, build identifier, model
identifier, harness version, and the manifest of active extensions. The
`package_version` on each extension lets readers detect extension schema
mismatches between sessions.

```json
{
  "type": "header",
  "goal": "login",
  "agents_md_hash": "sha256:abc...",
  "build_identifier": "debug-1.0.0",
  "model_identifier": "qwen3.6-35b-a3b@8bit",
  "harness_version": "0.1.0",
  "extensions": [
    {
      "namespace": "router",
      "package_version": "1.2.3",
      "contract_version": "1.0.0"
    }
  ],
  "config": {"turn_budget_ms": 30000}
}
```

### `turn`

One record per perception-action turn. `observation.extensions` and
`diff.extensions` are namespace-keyed maps so each extension's contribution
can be sliced out by readers without parsing the core payload.

```json
{
  "type": "turn",
  "index": 0,
  "observation": {"core": {}, "extensions": {}},
  "stability": {"policy": "action_relative"},
  "proposed_action": {"tool": "core.tap"},
  "validation": {"result": "ok", "retries": 0},
  "executed_action": {"tool": "core.tap"},
  "diff": {"core": {}, "extensions": {}},
  "summary_update": "tapped login button",
  "model_metadata": {
    "served_model_id": "claude-sonnet-4-6",
    "provider_request_id": "msg_01",
    "usage": {
      "model_calls": 2,
      "input_tokens": 6100,
      "output_tokens": 180,
      "model_latency_ms": 4200,
      "mean_time_to_first_token_ms": 900,
      "output_tokens_per_second": 55.4,
      "calls": [
        {"outcome": "schema_rejection", "latency_ms": 2000, "input_tokens": 3000, "output_tokens": 60},
        {"outcome": "ok", "latency_ms": 2200, "input_tokens": 3100, "output_tokens": 120}
      ]
    }
  }
}
```

`model_metadata.usage` counts every model call the turn made, including
schema and validator retries, which are billed like any other call. Each
call's `outcome` is `ok`, `schema_rejection`, `transport_error` or `error`.
Token counts are the provider's own figures; a call the provider reported
nothing for (a dead stream, a custom provider) is counted in
`calls_without_usage` instead. Cache read and write tokens are not reported
yet.

### `extension_disabled`

Emitted when an extension is auto-disabled mid-session (e.g. after
repeated failures). The `turn` field is the index of the next turn
the extension is absent from — the timeline panel renders this as
the auto-disable point.

```json
{
  "type": "extension_disabled",
  "namespace": "dio",
  "reason": "auto_disabled_after_3_failures",
  "turn": 7
}
```

### `footer`

Always written exactly once on `close()`, including on
`harness_error` paths. `outcome` is one of `done`, `budget_exhausted`,
`harness_error`. `harness_error` is present **only** when
`outcome == "harness_error"`.

```json
{
  "type": "footer",
  "outcome": "budget_exhausted",
  "final_summary": "ran out of turns",
  "total_turns": 25,
  "total_duration_ms": 30000,
  "usage": {
    "provider": "anthropic",
    "model": "claude-sonnet-4-6",
    "model_calls": 27,
    "input_tokens": 512000,
    "output_tokens": 9100,
    "model_latency_ms": 61000,
    "mean_time_to_first_token_ms": 850,
    "output_tokens_per_second": 61.2,
    "estimated_cost_usd": 1.6725,
    "price": {"input_per_mtok": 3.0, "output_per_mtok": 15.0, "source": "built-in 2026-10-17"}
  }
}
```

`usage` totals every call in the run. `estimated_cost_usd` is always
present: a number when the model has a price, otherwise `null` (unset, never
zero). A local `swift-infer` model has no built-in price. Prices come from
`ModelPricing` (`LeonardConfig.pricing`): a dated built-in table of list
prices, or an `override` that applies to every model.

On crash:

```json
{
  "type": "footer",
  "outcome": "harness_error",
  "final_summary": "crashed",
  "total_turns": 4,
  "total_duration_ms": 5000,
  "harness_error": "connection_lost"
}
```
