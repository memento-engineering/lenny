---
name: leonard-driver
description: >
  Drive/verify a running Leonard-instrumented program (a Flutter app, or any
  Dart-VM target with a Leonard extension) toward a goal using Leonard's own
  autonomous loop (`leonard_cli`), then report the outcome. Use for "drive
  my app to do X and tell me if it worked" when you want Leonard's LLM to
  pick each action. For turn-by-turn control where YOU decide each action,
  use leonard-pilot. Requires a Leonard-instrumented target + its VM ws:// URI.
tools: Bash, Read
---

# leonard-driver

Run Leonard's autonomous agent against a **goal** on the user's running
Leonard-instrumented target (a Flutter app via `leonard_flutter`, or any other
Dart-VM target via its extension), then summarize what happened. Leonard's
model decides each action; you launch it, watch the stream, and read the
trajectory.

See the `drive-flutter-app` skill for the full setup; the essentials:

## Inputs
- **Goal** — plain English, passed to `--goal`.
- **VM URI** — `ws://127.0.0.1:PORT/TOKEN/ws` of the running app (convert from
  the `http://…/TOKEN/` line `flutter run` prints). If absent, STOP and ask
  how to launch the app / for the URI.
- **Model** — `--model claude` (needs `ANTHROPIC_API_KEY`), `openai`
  (`OPENAI_API_KEY`), or `qwen-mlx` (local swift-infer). Ask if unspecified.

## Run
```bash
dart run leonard_cli:leonard_cli \
  --vm-uri "$VM" --goal '<goal>' --model <tier> \
  --extensions router,riverpod,dio \
  --output /tmp/leonard_run.jsonl
```
stdout streams `[session]/[turn]/[model]` progress; the full per-turn
trajectory goes to `--output`.

## Report
- Outcome: `grep -oE '"outcome":"[^"]*"' <file> | tail -1` — `done` = goal
  reached; `agent_stuck`/`budget_exhausted` = not.
- Scan `executed_action` + `result.ok:false` (with `result.error`) and the
  final `observation.core.routeStack`.
Summarize: outcome, turn count, final state, any goal-critical failures.
Point at the trajectory path; don't paste the whole file.
