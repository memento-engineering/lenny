# Changelog

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
