# leonard_acp

ACP (Agent Client Protocol) model provider for Leonard. It drives any
ACP-compatible coding agent as a per-turn decision oracle behind
`leonard_agent`'s `ModelProvider` seam, so `leonard_cli` can steer a live app
with an external agent instead of a hosted model.

Part of the [lenny](https://github.com/memento-engineering/lenny) workspace.
