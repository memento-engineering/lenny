# Agent Operating Guide

This file is read once per session and pinned to the model's system prompt.
Adapt it to your app — the agent will read whatever you put here.

## What the agent sees each turn

- Running summary (your evolving understanding of the app state)
- Per-turn diff of the observation tree (core fragment + plugin fragments)
- Last N actions with their results

## Last N actions

The harness keeps a sliding window of the most recent actions and feeds it
back to the model so it can plan multi-step interactions. Default N is 10.

## Tools available

The merged tool list is regenerated each turn from the active plugin set.
Auto-disabled plugins disappear from the list mid-session.

## swift-infer gateway

When the CLI is run with `--model qwen-mlx`, requests go through a local
swift-infer gateway. The wire contract is identical to factoryskills'
`fs agent` (`factoryskills/internal/agent/agent.go`) so the same gateway
deployment serves both clients.

Environment variables:

- `SWIFT_INFER_AGENT_TOKEN` — sent as `Authorization: Bearer <token>`.
  Same name `fs agent` reads; one shell export covers both.
- `SWIFT_INFER_ENDPOINT` — base URL of the gateway. Defaults to
  `http://localhost:8080`.

Per-run tracing: every request is stamped with `X-Session-Id` and
`X-Conversation-Id: exploration-<sessionId>-<unixMs>` so one exploration
run groups under one conversation in the gateway dashboard.
`X-Swift-Infer-Capture-Bodies: true` is on by default — inspect a run
with `GET $SWIFT_INFER_ENDPOINT/v1/conversations/<conversation-id>`.

See `packages/exploration_cli/README.md` for the full table and the
reference implementation in `factoryskills/internal/agent/agent.go`.
