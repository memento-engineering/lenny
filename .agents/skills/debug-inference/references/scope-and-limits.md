# What this skill can't tell you

When your diagnostic flow hits a dead end, it's probably one of these. Each entry points at the follow-up bead (if tracked).

## Raw token streams

The read-side store persists turns (complete messages) and metrics — not the token-by-token SSE stream the model emitted. If you need to see the actual streaming behavior (timing between tokens, partial tool-call formation, early token distribution), subscribe to `/v1/events` or the MQTT broker live.

Tracked for a dedicated skill: **`swift-infer-ph2`** (`watch-inference`). Not written yet.

```
# Live tail via SSE (not covered by this skill):
curl -N -H "Authorization: Bearer $SWIFT_INFER_ADMIN_TOKEN" \
  http://127.0.0.1:8080/v1/events
```

## Mux candidate decisions

When a MuxNode runs best-of-n, first-above-threshold, or cascade, it scores multiple candidates and picks one. Today, **only the winning candidate's metrics are stored**. The losing candidates' outputs, scores, and selection reasoning are not persisted — `trace.mux` is always `null`.

Tracked: **`swift-infer-0qg`** (persist MuxNode candidate decisions).

Implication for diagnosis: if you see `routing_reason: mux-*`, you can tell *which* strategy was used but not *what the other candidates produced*.

## Embedding vectors

No vector index is maintained on request text. The `/v1/embeddings` endpoint serves inference to callers but does not index stored `conversation_turns` content. Search (`/v1/requests?q=`) is lexical (SQLite FTS5), not semantic.

Tracked: **`swift-infer-p9l`** (Postgres + pgvector migration) lists pgvector as a driver; semantic search will become available when that lands.

## Request bodies when capture was off

If the caller didn't send `X-Swift-Infer-Capture-Bodies: true`, no `conversation_turns` rows exist for that request. You'll see:

- `trace.request.messages == null`
- `trace.response.content == null`, `thinking_content == null`, `tool_calls == null`
- `conversations[*].turn_count == 0`
- `/v1/requests?q=...` won't match it (nothing to search against)

`metrics` is still fully populated. If you need bodies for future runs, ask the caller to opt into capture.

## Feedback / ratings on requests

This skill doesn't cover `/v1/feedback` (user / agent ratings attached to a request_id). It's admin-scoped like the rest, and useful for post-hoc quality triage — but it's a separate diagnostic axis.

## What the model was *thinking* between turns

`thinking_content` is the model's own chain-of-thought when the model emits one (e.g. Qwen3-Coder). It's not a runtime trace — it's the model's self-narration. Not every model emits thinking, and even when they do, it only shows what the model chose to say.
