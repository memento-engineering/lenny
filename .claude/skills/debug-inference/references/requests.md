# /v1/requests

Search and filter recent requests. This is your **entry point** when you don't have a specific `request_id` or `conversation_id` and need to hunt by keyword, time window, or conversation scope.

## Request

```
curl -s -H "Authorization: Bearer $SWIFT_INFER_ADMIN_TOKEN" \
  "http://127.0.0.1:8080/v1/requests?since=2026-04-21T18:00:00Z&q=parse&limit=20"
```

## Response shape

```json
{
  "count": 7,
  "requests": [
    {"request_id": "req_xyz", "model": "qwen3-coder-next", "timestamp": "2026-04-21T18:32:00Z", "turn_count": 6},
    ...
  ]
}
```

`count` is the total matching requests before `limit`/`offset` pagination — use it to know whether to page further.

## Query parameters

| Param | Default | Behavior |
|---|---|---|
| `conversation_id` | — | restrict to one conversation_id (exact match) |
| `since` | — | ISO8601 timestamp, inclusive lower bound on `requests.timestamp` |
| `until` | — | ISO8601 timestamp, inclusive upper bound |
| `q` | — | full-text search across captured turn content (see syntax below) |
| `limit` | 50 | clamped to `[1, 500]` |
| `offset` | 0 | floored at 0 |

All filters combine with `AND`. Omitting `q` skips the FTS join — cheaper for time/conversation-only queries.

## Search syntax (`?q=`)

SQLite FTS5. Pass the query URL-encoded. Key operators:

- **Bare tokens**: `q=parse` matches any turn containing "parse".
- **Phrase**: `q="failed to parse"` matches the exact phrase (note: encoded as `%22failed%20to%20parse%22`).
- **Boolean**: `q=failed AND (parse OR json)` — combine terms.
- **Negation**: `q=error NOT timeout` — exclude a term.
- **Proximity**: `q=NEAR(failed parse, 5)` — words within 5 tokens.

The server returns `400 {"error":"invalid_query"}` if the FTS5 syntax is malformed.

## Worked example

"Show me requests in conversation `conv_1` from the last hour that mentioned 'retry':"

```
curl -s -H "Authorization: Bearer $SWIFT_INFER_ADMIN_TOKEN" \
  --data-urlencode "conversation_id=conv_1" \
  --data-urlencode "since=2026-04-21T17:00:00Z" \
  --data-urlencode "q=retry" \
  --data-urlencode "limit=20" \
  -G "http://127.0.0.1:8080/v1/requests"
```

Drill from there into `/v1/trace/:request_id` (see `trace.md`).

## Caveat

`?q=` only matches turn `content` — if body capture was off for a request, its content is not searchable. Requests without captured bodies still appear in unfiltered/time-filtered results with `turn_count: 0`.
