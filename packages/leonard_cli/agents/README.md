# Claude Code agents for driving lenny

Two ways to drive a lenny-instrumented Flutter app from Claude Code — no MCP.
These `.md` files are **subagent definitions**; `.claude/agents/` is gitignored,
so they live here (tracked) and you copy them in to activate:

```bash
cp packages/leonard_cli/agents/lenny-*.md .claude/agents/
```

Both require a running, lenny-instrumented app and its VM-service ws:// URI
(`ws://127.0.0.1:PORT/TOKEN/ws` — convert from the `http://…/TOKEN/` line that
`flutter run` prints).

## `lenny-pilot` — Claude Code is the brain (turn-by-turn)

You (Claude) observe → decide → act each turn over lenny's VM-service tool
surface via the stateless helper `bin/leonard_drive.dart`:

```bash
DRIVE="dart run packages/leonard_cli/bin/leonard_drive.dart"
$DRIVE tools   --vm-uri "$VM"                                   # tool manifest
$DRIVE observe --vm-uri "$VM"                                   # full observation JSON
$DRIVE invoke  --vm-uri "$VM" --tool core.tap --args '{"node_id":5}'
```

No model API keys, no lenny LLM — the decisions are yours.

## `lenny-driver` — orchestrate lenny's own autonomous loop

Shells `leonard_cli --goal …`, which drives with lenny's built-in LLM
(`--model qwen-mlx|claude|openai`), streams per-turn progress, and writes a
trajectory JSONL the agent reads to report the outcome. Use for "drive to this
goal and tell me what happened."

See each file's front-matter `description` for when to pick which.
