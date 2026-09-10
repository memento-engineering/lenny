# Changelog

## 0.3.1

- Fix: schema-declared integer and number tool arguments now normalize lossless
  quoted SwiftInfer numerics before strict `ActionSchema` validation. Outgoing
  schemas, `ActionValidator`, and retry budgets remain strict.

## 0.3.0

Promotes `0.3.0-rc.1` to stable. The candidate's full change list is under that
entry below; the break is restated here because this is the version a consumer
on 0.2.x upgrades to.

- **Breaking: owning VM-service connections live in `leonard_agent_io.dart`.**
  The static `connect` constructors — `VmServiceClient.connect`,
  `LeonardSession.connect` and `MultiHostSession.connectAll` — are gone from the
  default, web-safe library. Migration: import
  `package:leonard_agent/leonard_agent_io.dart` and call the top-level
  `connectVmServiceClient`, `connectLeonardSession` or `connectMultiHostSession`.
  A consumer that only wraps an already-connected `VmService`
  (`VmServiceClient.fromVmService`) is unaffected.
- **Breaking: `SwiftInferChatOptions`'s sampling fields are nullable.**
  `maxTokens`, `temperature`, `topP`, `topK`, `presencePenalty` and
  `repetitionPenalty` moved from `int`/`double` to `int?`/`double?`, so an unset
  override is omitted from the request instead of being sent as a default.
  Migration: null-check before reading one.
- Fix: device tool descriptors carried in a handshake are parsed into agent
  manifest entries and core descriptors route through `coreTools`, so validation
  rejects a malformed call before device dispatch. A legacy names-only handshake
  keeps the permissive projection (lenny#123).
- Add: the loop driver and conversation builder carry the trim-proof scratchpad,
  so a remembered result survives history trimming and is read back by recall
  (lenny#116).

## 0.3.0-rc.1

- **Breaking: owning VM-service connections moved to `leonard_agent_io.dart`.**
  The static `connect` constructors — `VmServiceClient.connect`,
  `LeonardSession.connect` and `MultiHostSession.connectAll` — are gone from the
  default, web-safe library. Migration: import
  `package:leonard_agent/leonard_agent_io.dart` and call the top-level
  `connectVmServiceClient`, `connectLeonardSession` or `connectMultiHostSession`.
  A consumer that only wraps an already-connected `VmService`
  (`VmServiceClient.fromVmService`) is unaffected and stays on
  `leonard_agent.dart`.
- Fix: model-response transport faults are classified as retryable failed turns
  and their diagnostic context carries into the terminal agent-stuck footer. Any
  exception still escaping the session loop is named and scrubbed, so a harness
  error is never anonymous.
- Fix: prior reasoning replays as native thinking blocks in assistant history,
  so swift-infer populates reasoning content without template-specific marker
  parsing.
- Fix: unset sampling overrides are omitted rather than sent; shared driver
  token and effort defaults are added, with operator overrides.
- Fix: the swift-infer qwen tier advertises its native context window, and the
  dogfood harness reads the shared capability registry.
- Fix: tooltip-only semantics are promoted to labels, distinct tooltips are
  preserved as hints, and the optional field carries through typed observations,
  so icon buttons are addressable by drivers.
- Fix: self-drive completion is gated on observed timeline evidence — a
  scenario-declared node pattern must match and captured row tokens are
  cross-checked against the completion reason — and diagnostic evidence is
  preserved when an observation fails.
- Raise the `leonard_contract` floor to `^0.2.2`; the declared `^0.2.0` floor was
  unsatisfiable against this package's own `genesis_perception` range.

## 0.2.0

- Breaking: VM-service methods now use `ext.leonard.*`. Construct names with
  `kLeonardExtensionPrefix` from `leonard_contract`.
- The VM-service client now consumes the shared Leonard wire contract.

## 0.1.6

- Provider response metadata is now persisted with the trajectory turn. The
  served model id and the streamed result identifier carry through model
  decisions into trajectory turns, so swift-infer observability stays on
  dartantic's standard result-identifier seam.
- New `ModelDecision.modelMetadata` (optional, defaults to empty).
  Dartantic-backed providers populate `served_model_id` and an explicit
  `provider_request_id`; custom providers may leave it empty.

## 0.1.5

- Perception nodes now carry `identifier` and `value` end-to-end to the brain.
  `SemanticsNode` parses and re-emits the stable, locale-independent
  `identifier` (from `Semantics(identifier:)`) and the node's `value`
  (text-field contents / secure-field bullets); both join `==`/`hashCode`, so a
  field filling in shows up in the diff. The host emitted these already — the
  agent model had been dropping them, so the brain only saw them on the native
  channel.
- The bundled agent guide (`kDefaultAgentsMd`) documents the split: read `label`
  to understand what a node is, use `identifier` as the stable handle for
  addressing it across locales/sessions, and always act by integer `node_id`.

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
