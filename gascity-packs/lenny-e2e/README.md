# lenny-e2e

A shareable [Gas City](https://github.com/gastownhall/gascity) pack that runs a
**live-device Leonard E2E** against any Flutter app and verifies the
agent drives it to goal completion.

It ships one generic formula, `lenny-e2e-session`: one supplied goal → one
trajectory → a PASS/FAIL verdict. The variable-length perception-action loop
lives inside `leonard_cli` / `LoopDriver`; this formula is the *outer*
orchestration — pre-flight, launch, run, inspect, triage — expressed as agent
contracts a worker executes.

## Prerequisites

- A Flutter app under test, built from your working tree, with an `ios/` project.
- A **wired** iOS device (USB — wireless breaks the VM-service tunnel) or a
  running simulator.
- `leonard_cli` available (a path dependency in your workspace, or globally
  activated).
- For `--model qwen-mlx`: `SWIFT_INFER_ENDPOINT` + `SWIFT_INFER_AGENT_TOKEN` in
  the environment. For `claude`: `ANTHROPIC_API_KEY`. For `openai`:
  `OPENAI_API_KEY`.

## Use it

Import into your workspace `pack.toml`:

```toml
[imports.lenny-e2e]
source = "../gascity-packs/lenny-e2e"
```

Pour a session, injecting your own parameters:

```bash
bd mol pour lenny-e2e-session \
  --var goal="Log in with email demo@example.com and password password, then open Settings and turn on Dark Theme" \
  --var model=qwen-mlx \
  --var app_dir=/abs/path/to/your/flutter/app
```

| Variable | Default | Meaning |
|----------|---------|---------|
| `goal` | *(required)* | The prompt the agent drives toward. **Specify it fully** — include any credentials or target state the agent cannot infer from the screen. |
| `model` | `claude` | `claude` \| `qwen-mlx` \| `openai`. |
| `app_dir` | *(required)* | Absolute path to the Flutter app (dir with `pubspec.yaml` + `ios/`). |
| `device` | *(first wired)* | `flutter -d <id>` target. Empty = the single attached non-wireless device. |
| `extensions` | `router,riverpod,dio` | Extension namespaces to enable. |
| `cli` | `dart run bin/leonard_cli.dart` | Invocation prefix for `leonard_cli`. |

## Extend it

This pack is intentionally generic. To build a regression suite, compose your
own formula that pours `lenny-e2e-session` once per scenario (different `goal`,
same `app_dir`/`model`) and aggregates the verdicts — keep that suite in your
own (private) pack so this one stays app-agnostic.

## A note on goal specification

The agent perceives the app only through a structured observation; it cannot see
secrets or remember app-specific facts. A terse goal like "Sign in" fails on an
app whose only valid credentials are unknown to the agent. Put the knowable
facts in the goal (`demo@example.com` / `password`), or rely on the app's own
defaults — don't expect the agent to guess.
