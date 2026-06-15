# /v1/trace/:request_id

Full reconstruction of a single inference request — messages in, response out, metrics around, mux decision (when persisted).

## Request

```
curl -s -H "Authorization: Bearer $SWIFT_INFER_ADMIN_TOKEN" \
  http://127.0.0.1:8080/v1/trace/req_abc123
```

Returns `404 {"error":"not_found"}` if no such request_id.

## Response shape

Top-level keys (always present): `request`, `response`, `metrics`, `mux`.

```json
{
  "request": {
    "id": "req_abc123",
    "conversation_id": "conv_1" | null,
    "session_id": "sess_1" | null,
    "model": "qwen3-coder-next",
    "timestamp": "2026-04-21T18:30:00Z",
    "messages": [ {"role": "system", "content": "..."}, {"role": "user", "content": "..."} ] | null
  },
  "response": {
    "content": "model output text" | null,
    "thinking_content": "model's chain of thought" | null,
    "tool_calls": [ {"id": "c1", "name": "...", "arguments": {...}} ] | null,
    "truncated": false
  },
  "metrics": {
    "node_id": "mlx-qwen3-coder",
    "routing_reason": "model-match",
    "ttft_ms": 35.2,
    "total_duration_ms": 412.7,
    "tokens_per_sec": 88.1,
    "prompt_tokens": 512,
    "completion_tokens": 64,
    "mean_logprob": -0.42,
    "timestamp": "2026-04-21T18:30:00Z"
  },
  "mux": null
}
```

## When body capture was off

If the caller didn't send `X-Swift-Infer-Capture-Bodies: true`, these fields are null:

- `request.messages`
- `response.content`, `response.thinking_content`, `response.tool_calls`

`metrics` is still fully populated — you can diagnose timing/quality without prompts.

## Key field rules

- `response.truncated` is `true` iff the assistant turn was stored with role `assistant_truncated` (hit a max-token or stop-sequence limit mid-generation).
- `response.tool_calls` is returned as a **parsed JSON array** when the stored value is valid JSON, or `null` when parsing fails or nothing was captured.
- `mux` is always `null` today. Persisted candidate decisions are tracked in `swift-infer-0qg`.

## Source of truth

`Sources/SwiftInferServer/Routes/TraceRoute.swift`. When the response diverges from this doc, the code is right — flag the drift.
