---
name: drive-with-leonard
description: >
  Drive and verify a running program with an LLM via Leonard — observe its
  runtime state over the Dart VM service, act with tools, work toward a goal,
  check the outcome. Leonard is a Dart-VM tool: a Flutter app is one target;
  external processes / pure-Dart programs are others. Use when asked to test,
  drive, verify, or exercise a running app/process end-to-end.
---

# Drive a running program with Leonard

Leonard wires an LLM straight into a **running Dart-VM program** over the VM
service: it observes the runtime's state (a structured perception tree), calls
tools to act, and works toward a goal — turn after turn. The agent core
(`leonard_agent`) is **pure Dart and target-agnostic**; what's being driven is
a *target*, contributed by an extension:

- **Flutter app** — `leonard_flutter` (the `LeonardBinding` host). Fully wired
  for **live driving** today.
- **External process / pure-Dart target** — an extension in Leonard's pure-Dart
  vocabulary; e.g. `leonard_tmux` observes tmux sessions/panes/output and
  contributes `tmux.send_keys` / `tmux.new_session`, depending only on
  `leonard_agent` (no Flutter). See "Non-Flutter targets" below for the current
  state of live driving.

## Driving a Flutter app (fully wired)

### Instrument `main()` (once)

```yaml
dependencies:
  leonard_flutter: ^0.1.0
dev_dependencies:
  leonard_cli: ^0.1.0
```

```dart
import 'package:leonard_flutter/leonard_flutter.dart';

void main() => LeonardBinding.run(MyLeonardApp());

class MyLeonardApp implements LeonardApp {
  @override
  LeonardAppConfig build(LeonardAppContext ctx) => LeonardAppConfig(
        extensions: <LeonardExtension>[/* optional: router/riverpod/dio */],
        app: const MyMaterialApp(), // your existing root widget
      );
}
```

`LeonardBinding.run` is debug/profile-only (a no-op passthrough in release).
`CoreExtension` (tap/scroll/enter_text/…) is always on.

### Run and connect

```bash
flutter run -d <device> --no-devtools > /tmp/app.log 2>&1 &
grep "Dart VM Service on" /tmp/app.log   # http://127.0.0.1:PORT/TOKEN/
# websocket form: ws://127.0.0.1:PORT/TOKEN/ws
```

## Drive (any target, over the VM service)

Autonomous — Leonard's own loop picks each action:

```bash
dart run leonard_cli:leonard_cli \
  --vm-uri 'ws://127.0.0.1:PORT/TOKEN/ws' \
  --goal '<plain-English goal>' --model claude --output /tmp/run.jsonl
```

`--model`: `claude` (`ANTHROPIC_API_KEY`), `openai` (`OPENAI_API_KEY`), or
`qwen-mlx` (local swift-infer). Add `--extensions <ns,…>` for any registered
extensions (e.g. `router,riverpod,dio`, or `tmux`).

Turn-by-turn — you decide each action:

```bash
DRIVE="dart run leonard_cli:leonard_drive"
$DRIVE tools   --vm-uri "$VM"
$DRIVE observe --vm-uri "$VM"
$DRIVE invoke  --vm-uri "$VM" --tool core.tap --args '{"node_id":12}'
```

Observations expose each node's `id`, `role`, `label`, `actions`, `rect`, and —
on scrollables — `scroll: {pos, min?, max?}`. Non-core extensions contribute
their own tools/fragments under their namespace.

## Verify

`--output` trajectory: `footer.outcome == done` = goal reached
(`agent_stuck`/`budget_exhausted` = not). Check per-turn `result.ok` and the
target's route/state.

```bash
grep -oE '"outcome":"[^"]*"' /tmp/run.jsonl | tail -1
```

## Non-Flutter targets (current state)

The extension/perception model is target-agnostic — `leonard_tmux` is the proof
(pure Dart, observes an external process). **Today the live VM-service host
that exposes `ext.exploration.*` for `leonard_cli` to drive ships in
`leonard_flutter` (`LeonardBinding`).** A pure-Dart host (so a non-Flutter
program can be driven live by `leonard_cli`) is the next piece; until then,
non-Flutter extensions are used as a **library** (call `extension.observe()` /
`extension.executeAction(...)` directly — see `leonard_tmux/example/main.dart`).
Don't assume `dart run leonard_cli` drives a non-Flutter target over the VM
service yet.
