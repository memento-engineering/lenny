# Changelog

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
