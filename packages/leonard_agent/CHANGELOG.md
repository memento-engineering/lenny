# Changelog

## 0.1.1

- Fix: bound runaway model output. The swift-infer provider now aborts a
  response once it streams a large amount of reasoning text with no tool
  call in sight, surfacing a retryable `SchemaRejection` instead of letting
  weaker models ruminate all the way to `max_tokens` — the "endless stream,
  no tool call" failure. The loop retries with a fresh sample.

## 0.1.0

Initial release.
