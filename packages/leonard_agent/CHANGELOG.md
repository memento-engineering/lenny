# Changelog

## 0.1.4

- Multi-host attach: `MultiHostSession` attaches to N VM-service hosts at once,
  merges each host's perception fragment into one observation (side-by-side,
  keyed by namespace), and routes each tool call to the owning host by namespace
  (`core.*` → the Flutter host, `native.*` → the native channel). A new
  `SessionSurface` interface is implemented by BOTH the unchanged single-host
  `LeonardSession` and `MultiHostSession`, so the loop drives either
  transparently. The agent context-switches by perception, not by hardcoded
  mode flags.

## 0.1.3

- `HandshakeResult` gains a `capabilities` field: host-level features that are
  reachable but are NOT namespaced tools (so they never appear under
  `extensions`) — notably `screenshot`. The handshake parse reads the new
  `capabilities` array and is tolerant of its absence (older bindings parse to
  an empty list). Lets a driver list `screenshot` where agents look instead of
  concluding "no such capability" from the tool manifest alone.

## 0.1.2

- Adopt dartantic as the model-backend seam: a single `DartanticModelProvider`
  drives any backend — swift-infer via lenny's custom `ChatModel`, Anthropic and
  OpenAI via stock dartantic models. The hand-rolled per-provider classes are
  removed; the loop keeps retry ownership and the `SchemaRejection` contract.
- Anthropic backend defaults are now compatible with extended thinking: a
  non-forcing `tool_choice` (`auto`) and no temperature override. Anthropic
  rejects a forcing `tool_choice` or any non-`1` temperature while thinking is
  enabled, so the previous defaults returned request-time `400`s when driving
  Claude. Thinking stays on; the driver's retry covers a rare prose-only turn.
- Fix (Anthropic): per-turn observation context is no longer dropped. The
  dartantic Anthropic mapper serializes only the `tool_result` block of a
  tool-bearing user message and discards sibling text parts, so from turn 1 on
  the model never saw the observation — it was driven blind after the first
  turn (the swift-infer path is unaffected; its mapper keeps the text). The
  Anthropic backend now folds the observation + diff into the `tool_result`
  body so the model sees the live screen every turn.
- Observation: expose scroll extent on scrollable nodes.

## 0.1.1

- Fix: bound runaway model output. The swift-infer provider now aborts a
  response once it streams a large amount of reasoning text with no tool
  call in sight, surfacing a retryable `SchemaRejection` instead of letting
  weaker models ruminate all the way to `max_tokens` — the "endless stream,
  no tool call" failure. The loop retries with a fresh sample.

## 0.1.0

Initial release.
