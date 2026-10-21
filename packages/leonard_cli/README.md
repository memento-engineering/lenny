# leonard_cli

Command-line entrypoint for Leonard. Connects to a
running Flutter VM service, drives the perception-action loop, and
streams a trajectory file to disk.

## Model providers

The `--model` flag selects a [`ModelTier`](lib/src/cli_args.dart) which
the [`provider_factory`](lib/src/provider_factory.dart) maps to a
concrete `ModelProvider`:

| Tier        | Provider             | Required env                      |
|-------------|----------------------|-----------------------------------|
| `claude`    | `AnthropicModelProvider` | `ANTHROPIC_API_KEY` (default)           |
| `qwen-mlx`  | `SwiftInferModelProvider` (local swift-infer gateway) | `SWIFT_INFER_AGENT_TOKEN` (when the gateway requires auth), `SWIFT_INFER_ENDPOINT` (optional, defaults to `http://localhost:8080`), `SWIFT_INFER_MODEL` (optional, defaults to `qwen3.6-35b-a3b-8bit`), `SWIFT_INFER_REASONING_EFFORT` (optional), `SWIFT_INFER_MAX_TOKENS` (optional, defaults to 16384) |
| `openai`    | `OpenAiModelProvider`    | `OPENAI_API_KEY`              |

## swift-infer gateway (qwen-mlx)

When `--model qwen-mlx` is selected, the CLI talks to the user's local
swift-infer gateway. The wire contract is intentionally identical to
`fs agent` (factoryskills' agent implementation in
`factoryskills/internal/agent/agent.go`) so the same gateway and
inspection tooling work for both clients.

### Environment variables

* `SWIFT_INFER_AGENT_TOKEN` — forwarded as
  `Authorization: Bearer <token>`. Same name `fs agent` uses; share one
  shell export for both. When unset (or empty), the CLI sends an
  unauthenticated request — useful when pointing at a gateway that has
  auth disabled, but the production gateway requires this.
* `SWIFT_INFER_ENDPOINT` — base URL of the gateway. Defaults to
  `http://localhost:8080` when unset or empty.
* `SWIFT_INFER_MODEL` — model id requested from the gateway. Defaults to
  `qwen3.6-35b-a3b-8bit` when unset or empty. Set it to any node the gateway
  serves (`curl "$SWIFT_INFER_ENDPOINT/v1/models"` lists them), e.g.
  `qwen3.8-40b-a3b-8bit`. The `--model-id` flag outranks this variable, which
  outranks the default; capabilities resolve from the id itself, so any
  `qwen3.*` node keeps vision + preserved thinking.
* `SWIFT_INFER_REASONING_EFFORT` — `reasoning_effort` sent on every
  `/v1/messages` request when resolved: one of `none`, `low`, `medium`, `high`,
  `xhigh`. Unset (or empty) means the field is omitted and the node's model-card
  default applies — except for a `qwen3.8*` model id, which defaults to `medium`
  because that template otherwise runs `xhigh`. The `--reasoning-effort` flag
  outranks this variable; an unparseable value fails the run loudly.
* `SWIFT_INFER_MAX_TOKENS` — `max_tokens` for a single response. Defaults to
  `16384` (thinking plus answer share this budget). The `--max-tokens` flag
  outranks this variable; a non-positive or non-numeric value fails the run
  loudly.

Every other sampling knob (`temperature`, `top_p`, `top_k`,
`presence_penalty`, `repetition_penalty`) is deliberately NOT sent by the CLI,
so the swift-infer node's per-model card values apply. `preserve_thinking` is
always sent — it is a reasoning-replay contract, not a sampling knob.

### Per-run conversation tracing

Every run mints a stable `sessionId` (`cli-<utc-iso8601>` slugged to
header-safe characters) and stamps every request with:

* `X-Session-Id: <sessionId>`
* `X-Conversation-Id: leonard-<sessionId>-<unixMs>` — one
  conversation per run, groups every turn for inspection. Mirrors
  `fs agent`'s `fsagent-<beadID>-<unixtime>` convention.
* `X-Swift-Infer-Capture-Bodies: true` — `captureBodies` is on by
  default for dev/PoC. The gateway captures both the request and
  response bodies so `GET $SWIFT_INFER_ENDPOINT/v1/conversations/<id>`
  returns the captured turn for inspection without re-running the
  agent.
* `Accept: text/event-stream` — SSE streaming for live `<think>…</think>`
  surfaces.

Example (default — cloud backend):

```sh
export ANTHROPIC_API_KEY=sk-ant-…
dart run leonard_cli \
  --vm-uri ws://127.0.0.1:54321/abc=/ws \
  --goal "open settings"
```

Example (opt-in — local swift-infer):

```sh
export SWIFT_INFER_AGENT_TOKEN=sk-…
export SWIFT_INFER_ENDPOINT=http://localhost:8080     # optional
export SWIFT_INFER_MODEL=qwen3.8-40b-a3b-8bit         # optional
export SWIFT_INFER_REASONING_EFFORT=medium            # optional
export SWIFT_INFER_MAX_TOKENS=16384                   # optional
dart run leonard_cli \
  --model qwen-mlx \
  --vm-uri ws://127.0.0.1:54321/abc=/ws \
  --goal "open settings"
# Inspect captured turn:
curl "$SWIFT_INFER_ENDPOINT/v1/conversations/leonard-cli-…"
```

## Run summary, tokens and cost

Every trajectory records the provider's token counts and model latency: per
turn under `model_metadata.usage`, and for the whole run under the footer's
`usage` (see the `leonard_agent` README for the shapes). Retries count as
calls. For CI, `--summary-json <path>` also writes one small JSON file per
run, so totals can be collected without parsing trajectories:

```json
{
  "schema": "leonard.run_summary/1",
  "exit_code": 0,
  "outcome": "done",
  "total_turns": 9,
  "total_duration_ms": 48000,
  "model_identifier": "claude",
  "trajectory": "trajectories/2026-10-17T10-00-00Z.jsonl",
  "usage": {"model_calls": 10, "input_tokens": 141000, "output_tokens": 2600, "estimated_cost_usd": 0.462, "...": "..."}
}
```

The cost estimate uses a dated built-in table of list prices for the hosted
models. A local `qwen-mlx` run, or a model not in the table, reports
`estimated_cost_usd: null`. To price a run yourself (an unlisted model, a
negotiated rate, or amortized owned hardware), pass dollars per million
tokens with `--price-input-per-mtok` and `--price-output-per-mtok`, or set
`LEONARD_PRICE_INPUT_PER_MTOK` and `LEONARD_PRICE_OUTPUT_PER_MTOK`. The flags
outrank the environment, and both values of a pair must be set.

Runs also record time to first token and output tokens per second, which is
the figure that matters when sizing local hardware.

## Verdicts and gate exit codes

The exit code alone does not say whether the app did the thing: a run that
spends its whole budget without reaching the goal still exits 0. The summary
says it instead, in three more fields:

```json
{
  "verdict": "fail",
  "reason": "budget exhausted after 50 turns without reaching the goal",
  "digest": ["… 38 earlier turns omitted", "#38 core.tap node_id=\"12\" → ok", "..."]
}
```

| Verdict | When |
|---|---|
| `pass` | The model called `core.done` (and every golden matched). |
| `fail` | Leonard drove the app and the goal was not met: the budget ran out, the app's VM service went away mid-drive, or a frame missed its golden. |
| `infra` | Leonard could not judge the app: no launch or attach, the provider was misconfigured, unreachable or too slow, the model could not produce a valid action, or the observation envelope was rejected. |

`digest` is the run's last turns, one line each, newest last, under 3000
characters: enough to tell a coding agent where the drive got stuck.

For a deterministic gate, `--gate-exit-codes` makes the process exit with the
verdict: **0 pass, 75 infra, 1 fail**. 75 is `EX_TEMPFAIL`, the code Gas City
reserves for a check that could not reach its infrastructure.
A usage error exits 75 too, and the last stderr line is the verdict and its
reason. `gc_pack/leonard` at the repository root wraps this as a Gas City
pack.

## Captured frames and image goldens

Every live-driving run writes PNG frames already carried by its trajectory
turns. By default, the frame directory is derived from the trajectory path:

```text
trajectories/
├── 20260507T141503Z.jsonl
└── 20260507T141503Z.frames/
    ├── turn-0000.png
    └── turn-0001.png
```

The same rule keeps frames inside the station's existing per-run directory:

```text
panel-selfdrive-20260507T141503Z/
├── outer.jsonl
├── outer.frames/
│   ├── turn-0000.png
│   └── turn-0001.png
├── driver.log
└── driver.status
```

`--frames-dir <dir>` overrides only frame placement. The CLI never deletes or
prunes frame or run directories; the caller owns retention. With no
`--goldens-dir`, the run is capture-only.

To compare the current run against PNG baselines, supply their directory:

```sh
dart run leonard_cli \
  --vm-uri ws://127.0.0.1:54321/abc=/ws \
  --goal "open settings" \
  --goldens-dir image_goldens
```

Frames are paired with goldens by filename. Image dimensions must match. A
pixel differs when any RGBA channel delta exceeds
`--golden-channel-tolerance` (default `8`), and the frame fails when the
differing-pixel ratio exceeds `--golden-max-diff-ratio` (default `0.0`).

To establish or replace baselines, run:

```sh
dart run leonard_cli \
  --vm-uri ws://127.0.0.1:54321/abc=/ws \
  --goal "open settings" \
  --goldens-dir image_goldens --update-goldens
```

Update mode creates the baseline directory, overwrites same-named files, and
prints every baseline written. It never compares in the same invocation. The
repository's comparator fixtures are PNGs under
`packages/leonard_cli/test/image_goldens/`; they are distinct from the JSON
observation goldens used by the Flutter perception-equivalence tests.

## Nightly dogfood

The nightly e2e test (`packages/leonard_agent/integration_test/dogfood/dogfood_e2e_test.dart`) is
self-pinned to local inference via its own `SwiftInferConfig` construction and does not
depend on `leonard_cli`'s `--model` default. The launchagent that runs the nightly
test (`scripts/launchd/run-dogfood.sh`) invokes `dart test` directly on the e2e test
file, bypassing the CLI entirely, so the default change has no effect on nightly behavior.

### See also

* `factoryskills/internal/agent/agent.go` — the reference
  implementation of this wire contract. lenny's swift-infer client is
  intentionally header-for-header symmetric with `fs agent`; if you
  add a new header to one, add it to the other.
* `lib/src/provider/swift_infer/swift_infer_config.dart` (in
  `leonard_agent`) — provider-side config surface, including the
  `extraHeaders` forward-compat bag.
