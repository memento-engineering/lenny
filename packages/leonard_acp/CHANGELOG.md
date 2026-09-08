# Changelog

## 0.2.0-rc.1

- Require `leonard_agent ^0.3.0-rc.1`. This package imports only the web-safe
  `leonard_agent.dart` surface, which that version keeps unchanged. No API
  changes in this package.

## 0.1.0

First release — the ACP (Agent Client Protocol) model provider for Leonard:
drives any ACP-compatible coding agent as a per-turn decision oracle behind
`leonard_agent`'s `ModelProvider` seam.
