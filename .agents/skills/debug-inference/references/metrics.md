# Metrics interpretation

Every request has a `metrics` row regardless of body capture. Here's what each field means and the rough thresholds for "normal" vs "worry."

Fetch aggregate stats:

```
curl -s -H "Authorization: Bearer $SWIFT_INFER_ADMIN_TOKEN" \
  "http://127.0.0.1:8080/v1/telemetry?limit=100"
```

## Field reference

### `ttft_ms` — time to first token (milliseconds)

How long from request received to first output token. Dominated by prompt-processing time.

- **Normal local MLX**: 20–200ms for typical prompts (1–2k tokens)
- **Long context**: scales roughly linearly with prompt_tokens
- **Worry**: `ttft_ms > 500` on a local model with short prompts → lifecycle eviction churn, Metal pipeline miss, or routing to an HTTP proxy leaf
- **Very bad**: `ttft_ms > 2000` → something loaded from cold

### `tokens_per_sec` — generation throughput

Output tokens per second, measured after first token.

- **Normal local MLX**: 40–120 tps depending on model size and quantization
- **FlashMoE**: 60–150 tps typical
- **HTTP proxy**: bounded by upstream provider
- **Worry**: `< 20` for a local model → KV cache thrashing, memory pressure, or unexpected quantization path

### `mean_logprob` — average log-probability of generated tokens

Model's confidence in its output, averaged across completion tokens. More negative = less confident.

- **Confident / typical**: `-0.1` to `-0.8`
- **Borderline**: `-0.8` to `-1.5` — check the content; model was hedging
- **Uncertain**: `< -1.5` — model was surprised by its own output; often correlates with refusals, hallucinations, or tool-call malformation
- **Very uncertain**: `< -2.5` — almost always indicates something wrong (wrong model for task, broken prompt template, adversarial input)

### `routing_reason` — why this node handled the request

Free-form string written by the router. Common values:
- `model-match` — exact match on requested `model` name
- `default` — no match, used first registered node
- `mux-best-of-n`, `mux-cascade-escalate` — emitted by MuxNode strategies
- `fallback-after-error` — a preferred node errored out

If you see a surprising `node_id` / `routing_reason` mismatch (e.g. a Qwen request routed to a GPT-4 HTTP proxy), model-name resolution likely broke.

### `prompt_tokens` vs `completion_tokens`

Ratio hints at shape:
- **Question-answer**: `prompt < 500`, `completion < 200`
- **Coding task**: `prompt > 2000`, `completion 500–3000`
- **Tool-calling loop**: typically short completions (`< 200`) repeated many times
- **Anomaly**: `completion_tokens == 0` with `total_duration_ms > 0` → model errored or refused mid-generation. Cross-check `response.truncated` and content.

## Cross-referencing

For a single request, pair the metrics with the trace body (`trace.md`) to interpret together. Low logprob with empty content is a different signal than low logprob with long content.
