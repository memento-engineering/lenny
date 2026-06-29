# Changelog

## 0.1.7

- The core semantics fragment now emits `identifier` (from
  `SemanticsData.identifier`, set via `Semantics(identifier:)`) alongside
  `label` and `value` — a stable, locale-independent key for addressing a node.
  Emitted present-only, so apps that set no identifiers are unaffected.

## 0.1.6

- The core semantics fragment now emits a `value` field (from
  `SemanticsData.value`) alongside `label`, so the harness sees a node's current
  value (e.g. a text field's contents) uniformly with the native channel's
  record shape.
- Stability: the settle loop no longer wedges when a framework callback stays
  registered across frames — the persistent-callback baseline is dropped from
  `isAnyBusy`, so a quiet frame is correctly reported as idle.

## 0.1.5

- `core.handshake` now advertises a `capabilities` list alongside the extension
  manifest. `screenshot` (the raw `core.screenshot` VM extension) is reachable
  but is not a namespaced tool, so it never appeared in the manifest — a driver
  listing tools would wrongly conclude "no screenshot". It is now reported as a
  capability, gated on the same debug/profile condition as the extension itself
  (absent in release).

## 0.1.4

- Extension contract extracted to the new `leonard_contract` package
  (Flutter-free): `LeonardExtension`, `LeonardTool`, `PerceptionExtension`,
  `ExtensionRegistry`, and the dispatch helpers now live there and are
  re-exported via `contract.dart`, so consumers are unaffected. Adds a
  `leonard_contract` dependency. The unused frame-callback and error-handler
  hooks were dropped, removing the `SchedulerBinding` / `FlutterErrorDetails`
  coupling from the contract; the binding's error-ring-buffer capture is
  unchanged.

## 0.1.3

- Perception serialization de-duplicated: `serializePerceptionFragment` now
  lives in `genesis_perception` and is re-exported here. Bumps the
  `genesis_perception` floor to `^0.1.2` (the version that introduced it).
- Observation: expose scroll extent (`pos` / `min` / `max`) on scrollable
  nodes, so the agent can see scroll position and bounds instead of guessing.

## 0.1.2

- Fix: a new agent handshake resets the session-terminated latch set by
  `core.done`. Previously, reusing one running app across multiple agent
  drives left the binding permanently terminated after the first drive's
  `core.done`, so every subsequent action returned `session_terminated` and
  the agent appeared stuck (model-agnostic). `core.handshake` now clears the
  latch — a handshake marks the start of a new session.

## 0.1.1

- Fix: ship the compiled DevTools extension bundle in the published package.
  0.1.0 omitted `extension/devtools/build/` because the repo-root `build/`
  `.gitignore` rule excluded it (`pub publish` honors `.gitignore`), so the
  "Leonard" DevTools tab was missing for consumers. The bundle is now
  un-ignored and shipped.

## 0.1.0

- Host `WidgetsBinding` (`LeonardBinding`) with a single-path perception
  observation pipeline (`PerceptionOwner`-backed serialization).
- `LeonardExtension` authoring contract; core fragment is perception-native.
- Ships the DevTools extension (the "Leonard" tab) via `extension/devtools/`.
- VM-service surface `ext.exploration.*` (protocol-stable).
