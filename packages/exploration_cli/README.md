# exploration_cli

Command-line entrypoint for lenny's exploration agent. Connects to a
running Flutter VM service, drives the perception-action loop, and
streams a trajectory file to disk.

## Model providers

The `--model` flag selects a [`ModelTier`](lib/src/cli_args.dart) which
the [`provider_factory`](lib/src/provider_factory.dart) maps to a
concrete `ModelProvider`:

| Tier        | Provider             | Required env                      |
|-------------|----------------------|-----------------------------------|
| `claude`    | `AnthropicModelProvider` | `ANTHROPIC_API_KEY` (default)           |
| `qwen-mlx`  | `SwiftInferModelProvider` (local swift-infer gateway) | `SWIFT_INFER_AGENT_TOKEN` (when the gateway requires auth), `SWIFT_INFER_ENDPOINT` (optional, defaults to `http://localhost:8080`) |
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

### Per-run conversation tracing

Every run mints a stable `sessionId` (`cli-<utc-iso8601>` slugged to
header-safe characters) and stamps every request with:

* `X-Session-Id: <sessionId>`
* `X-Conversation-Id: exploration-<sessionId>-<unixMs>` — one
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
dart run exploration_cli \
  --vm-uri ws://127.0.0.1:54321/abc=/ws \
  --goal "open settings"
```

Example (opt-in — local swift-infer):

```sh
export SWIFT_INFER_AGENT_TOKEN=sk-…
export SWIFT_INFER_ENDPOINT=http://localhost:8080  # optional
dart run exploration_cli \
  --model qwen-mlx \
  --vm-uri ws://127.0.0.1:54321/abc=/ws \
  --goal "open settings"
# Inspect captured turn:
curl "$SWIFT_INFER_ENDPOINT/v1/conversations/exploration-cli-…"
```

## Nightly dogfood

The nightly e2e test (`packages/exploration_agent/test/e2e/dogfood_e2e_test.dart`) is
self-pinned to local inference via its own `SwiftInferConfig` construction and does not
depend on `exploration_cli`'s `--model` default. The launchagent that runs the nightly
test (`scripts/launchd/run-dogfood.sh`) invokes `dart test` directly on the e2e test
file, bypassing the CLI entirely, so the default change has no effect on nightly behavior.

### See also

* `factoryskills/internal/agent/agent.go` — the reference
  implementation of this wire contract. lenny's swift-infer client is
  intentionally header-for-header symmetric with `fs agent`; if you
  add a new header to one, add it to the other.
* `lib/src/provider/swift_infer/swift_infer_config.dart` (in
  `exploration_agent`) — provider-side config surface, including the
  `extraHeaders` forward-compat bag.
