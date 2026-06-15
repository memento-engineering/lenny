# leonard_agent

Web-compatible harness library for the Flutter Exploration Agent. This
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
`plugin_disabled` records interleaved in execution order, exactly one
`footer` on the last line. The writer flushes after every record.

**Size budget:** sessions are expected to stay under 50 MB / 30 minutes
(PRD §23). Readers should stream rather than slurp.

Each record is a JSON object with a `type` discriminator and snake_case
keys.

### `header`

Session metadata: goal, AGENTS.md hash, build identifier, model
identifier, harness version, and the manifest of active plugins. The
`package_version` on each plugin lets readers detect plugin schema
mismatches between sessions.

```json
{
  "type": "header",
  "goal": "login",
  "agents_md_hash": "sha256:abc...",
  "build_identifier": "debug-1.0.0",
  "model_identifier": "qwen3.6-35b-a3b@8bit",
  "harness_version": "0.1.0",
  "plugins": [
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

One record per perception-action turn. `observation.plugins` and
`diff.plugins` are namespace-keyed maps so each plugin's contribution
can be sliced out by readers without parsing the core payload.

```json
{
  "type": "turn",
  "index": 0,
  "observation": {"core": {}, "plugins": {}},
  "stability": {"policy": "action_relative"},
  "proposed_action": {"tool": "core.tap"},
  "validation": {"result": "ok", "retries": 0},
  "executed_action": {"tool": "core.tap"},
  "diff": {"core": {}, "plugins": {}},
  "summary_update": "tapped login button",
  "model_metadata": {"tokens_in": 10, "tokens_out": 5, "duration_ms": 200}
}
```

### `plugin_disabled`

Emitted when a plugin is auto-disabled mid-session (e.g. after
repeated failures). The `turn` field is the index of the next turn
the plugin is absent from — the timeline panel (.24) renders this as
the auto-disable point.

```json
{
  "type": "plugin_disabled",
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
  "total_duration_ms": 30000
}
```

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
