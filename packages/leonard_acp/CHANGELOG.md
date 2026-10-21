# Changelog

## 0.2.2

- Fix: GitHub Copilot CLI sessions failed at the handshake. Leonard sent
  `initialize` with `clientCapabilities.fs: null`, and the Copilot CLI
  (1.0.82) rejects that with -32602 "Invalid params", so neither the CLI
  harness nor the DevTools panel could use Copilot. Leonard now sends `fs` as
  an explicit all-false object; it still grants the agent no file system and
  no terminal. Live probe: handshake in 0.4 s and a deny-all turn returning a
  bare Leonard action in 1.9 s on `claude-sonnet-5`.
- New public `leonardClientCapabilities()`, the capabilities sent in
  `initialize`.
- README: how to drive the DevTools panel with Copilot or Codex through
  `leonard_acp:dtd_host`.

## 0.2.1

Stable promotion of `0.2.1-dev.1`: the same content, published on the stable rung on Nico's promotion call (2026-10-15), after the Android (Pixel 7a), iOS 26.5 simulator and macOS live suites passed. The prerelease entries below carry the full list.

## 0.2.1-dev.1

- Add `DtdAcpHost`, which bridges ACP model providers over the Dart Tooling
  Daemon so the DevTools panel can run inference sessions through them.
- Add the `acpAgentSpecs` registry (`codex`, `copilot`),
  `AcpAgentSpec.withModelOverride`, and `AcpSession.availableModelIds` for
  selectable inference sessions.

## 0.2.0

Promotes `0.2.0-rc.1` to stable.

- **Breaking: requires `leonard_agent ^0.3.0`.** Migration: move the
  `leonard_agent` constraint to `^0.3.0`. This package imports only the web-safe
  `leonard_agent.dart` surface, which that version keeps unchanged, and has no
  API changes of its own.

## 0.2.0-rc.1

- Require `leonard_agent ^0.3.0-rc.1`. This package imports only the web-safe
  `leonard_agent.dart` surface, which that version keeps unchanged. No API
  changes in this package.

## 0.1.0

First release — the ACP (Agent Client Protocol) model provider for Leonard:
drives any ACP-compatible coding agent as a per-turn decision oracle behind
`leonard_agent`'s `ModelProvider` seam.
