---
name: debug-inference
description: Diagnose a past SwiftInferServer inference run. Use this skill to triage why another agent misbehaved — slow, refused, malformed tool call, truncated, uncertain, or wrong model routed — by querying stored telemetry + captured conversation turns.
---

# debug-inference

Diagnostic skill for triaging inference runs through the SwiftInferServer read-side API. You'll use this when another agent produced a weird output and you need to figure out why.

## Mental model

- A **request** is one inference call — always produces a metrics row in the `requests` table.
- A **conversation** groups related requests by `conversation_id` (optional header).
- **Conversation turns** hold the actual prompt/response/tool bodies — only stored when the caller opted in via `X-Swift-Infer-Capture-Bodies: true`.
- **Metrics are always present.** Turn bodies may not be. This skill handles both cases.

## Auth

Every endpoint below requires an admin-scope bearer:

```
Authorization: Bearer $SWIFT_INFER_ADMIN_TOKEN
```

Base URL: `http://127.0.0.1:8080` (local). See the `feedback_server_launchctl` memory if you need to bounce the server — never kill/start manually.

## Endpoints

| Endpoint | Purpose | Reference |
|---|---|---|
| `GET /v1/requests?...` | entry point — search/filter/paginate recent requests | `references/requests.md` |
| `GET /v1/trace/:request_id` | full reconstruction of one request (messages + response + metrics) | `references/trace.md` |
| `GET /v1/conversations/:conversation_id` | list requests in a conversation | `references/conversations.md` |
| `GET /v1/telemetry` | aggregate stats across recent requests | `references/metrics.md` |

## Where do I start?

Pick your entry point by what you already know:

- **Have a `request_id`?** → jump straight to `references/trace.md`.
- **Have a `conversation_id` (maybe from an X-Conversation-Id header the caller logged)?** → `references/conversations.md` to list its requests, then drill into `/v1/trace/:id`.
- **Have a symptom only** (refused, slow, truncated, bad tool call, uncertain output)? → `references/troubleshooting.md` for the symptom → query recipe.
- **Just a time window or keyword?** → `references/requests.md` to use `/v1/requests?since=&q=` as your search entry point.

Once you have a `request_id`, `trace.md` + `metrics.md` carry the interpretation burden.

## What this skill can't tell you

See `references/scope-and-limits.md` before going deeper — raw token streams, mux candidate decisions, and embedding vectors aren't in the read-side store. This matters when your diagnostic flow hits a dead end.
