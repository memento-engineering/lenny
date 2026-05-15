# Troubleshooting playbook

Start here when you have a **symptom** but no request_id. Pick the matching row, run the query, drill into the trace.

Every recipe assumes you have `$SWIFT_INFER_ADMIN_TOKEN` exported.

## Symptom → signal → query

### "Agent refused / output was empty"

Signal: `response.content` is empty/null and `completion_tokens` is suspiciously low.

```
curl -s -H "Authorization: Bearer $SWIFT_INFER_ADMIN_TOKEN" \
  "http://127.0.0.1:8080/v1/requests?since=2026-04-21T17:00:00Z&limit=50" | \
  jq '.requests[] | select(.turn_count > 0)'
```

Then for each candidate, `GET /v1/trace/:id` and inspect:
- `response.content` empty → refusal or early EOS
- `metrics.completion_tokens` low + `mean_logprob` very negative → model was uncertain and stopped
- `response.tool_calls` null but your caller expected tools → the prompt may have triggered a refusal

### "Tool call was malformed"

Signal: your tool-parsing layer errored, or the JSON was bad.

```
curl -s -H "Authorization: Bearer $SWIFT_INFER_ADMIN_TOKEN" \
  --data-urlencode "q=tool_call OR function_call OR xml_function" \
  -G "http://127.0.0.1:8080/v1/requests"
```

In the trace:
- `response.tool_calls == null` but `response.content` contains tool-shaped markup → model emitted a raw string instead of structured output. Likely the tool format wasn't set correctly (see the `project_qwen3_coder_xml_function` memory — Qwen3-Coder needs explicit `xml_function`).
- `response.tool_calls` is an array but values look wrong (missing id, empty args) → schema mismatch or truncation; check `response.truncated`.

### "Response was truncated"

Signal: `response.truncated == true` in the trace.

```
# No server-side filter for truncation yet; list recent and jq-filter.
curl -s -H "Authorization: Bearer $SWIFT_INFER_ADMIN_TOKEN" \
  "http://127.0.0.1:8080/v1/requests?since=2026-04-21T17:00:00Z&limit=100" | \
  jq '.requests[].request_id' | \
  while read -r rid; do
    curl -s -H "Authorization: Bearer $SWIFT_INFER_ADMIN_TOKEN" "http://127.0.0.1:8080/v1/trace/$(echo "$rid" | tr -d '"')" | \
      jq -r 'select(.response.truncated == true) | .request.id'
  done
```

Check `prompt_tokens` against the model's context window — often the prompt filled most of context and leaving little room to generate.

### "Response was slow"

Signal: `metrics.ttft_ms > 500` or `tokens_per_sec < 20` on a local model.

Pull telemetry aggregates to see whether it's systemic:

```
curl -s -H "Authorization: Bearer $SWIFT_INFER_ADMIN_TOKEN" \
  "http://127.0.0.1:8080/v1/telemetry?limit=500" | \
  jq '.records | map(select(.ttft_ms > 500)) | length'
```

For a single slow request, `trace.md` → `metrics.routing_reason` — unexpected node? Consider lifecycle eviction churn.

### "Model answered but logprobs are low" (uncertain output)

Signal: `metrics.mean_logprob < -1.5`.

Pull it with:

```
curl -s -H "Authorization: Bearer $SWIFT_INFER_ADMIN_TOKEN" \
  "http://127.0.0.1:8080/v1/telemetry?limit=200" | \
  jq '.records | map(select((.mean_logprob // 0) < -1.5))'
```

Inspect the trace's `request.messages` — usually a prompt-template mismatch, wrong model, or the task is out-of-distribution.

### "Wrong model was used"

Signal: `metrics.node_id` / `routing_reason` unexpected.

```
curl -s -H "Authorization: Bearer $SWIFT_INFER_ADMIN_TOKEN" \
  "http://127.0.0.1:8080/v1/telemetry?limit=100" | \
  jq '.records | group_by(.node_id) | map({node: .[0].node_id, count: length})'
```

Then trace a sample to see the `request.model` the caller asked for vs the `metrics.node_id` that served it.
