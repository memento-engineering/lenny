# /v1/conversations/:conversation_id

List requests in a conversation, newest first. Use this when you have a `conversation_id` (usually from an `X-Conversation-Id` header the caller logged) and want to see every request that was part of that session.

## Request

```
curl -s -H "Authorization: Bearer $SWIFT_INFER_ADMIN_TOKEN" \
  "http://127.0.0.1:8080/v1/conversations/conv_1?limit=20"
```

## Response shape

```json
{
  "conversation_id": "conv_1",
  "count": 42,
  "requests": [
    {"request_id": "req_abc123", "model": "qwen3-coder-next", "timestamp": "2026-04-21T18:32:00Z", "turn_count": 6},
    {"request_id": "req_abc122", "model": "qwen3-coder-next", "timestamp": "2026-04-21T18:31:45Z", "turn_count": 4}
  ]
}
```

- `count` is the **total** matching requests in the conversation, before pagination — use this to know whether to page further.
- `requests` is ordered by `timestamp DESC` (newest first).
- `turn_count` counts the stored `conversation_turns` rows for that request. If capture was off for a request, `turn_count` will be 0.
- An empty conversation returns `{"conversation_id":..., "count":0, "requests":[]}` with status `200` — not `404`.

## Pagination

- `?limit=` — defaults to 100, clamped to `[1, 500]`.
- `?offset=` — defaults to 0, floored at 0.

```
curl -s -H "Authorization: Bearer $SWIFT_INFER_ADMIN_TOKEN" \
  "http://127.0.0.1:8080/v1/conversations/conv_1?limit=50&offset=100"
```

## Typical drill path

1. List with `?limit=20` to get recent request_ids.
2. Identify the suspect request by timestamp or turn_count anomaly.
3. Jump to `/v1/trace/:request_id` — see `trace.md`.

When you don't know the conversation_id but have a keyword or time window, start with `/v1/requests` instead (see `requests.md`).
