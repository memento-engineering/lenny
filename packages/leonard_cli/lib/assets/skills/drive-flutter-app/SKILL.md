---
name: drive-flutter-app
description: >
  Drive and verify a running Flutter app end-to-end with an LLM, via Leonard.
  Instrument the app, connect over the Dart VM service, run a plain-English
  goal, and check the outcome. Use when asked to test, drive, verify,
  exercise, or "click through" a Flutter app's real UI — especially flows a
  widget test can't easily cover (navigation, multi-screen, live state).
---

# Drive a Flutter app with Leonard

Leonard lets an LLM drive a **running** Flutter app: it observes the app's
semantics tree, calls tools (tap, enter_text, scroll, …) over the Dart VM
service, and works toward a goal. Use this to verify behavior on the live app.

## 0. Prerequisites (one-time)

The app must depend on `leonard_flutter`, and you need `leonard_cli` to drive:

```yaml
# pubspec.yaml
dependencies:
  leonard_flutter: ^0.1.0
dev_dependencies:
  leonard_cli: ^0.1.0
```

Instrument `main()` so the Leonard binding is installed before any Flutter
objects are built:

```dart
import 'package:leonard_flutter/leonard_flutter.dart';

void main() => LeonardBinding.run(MyLeonardApp());

class MyLeonardApp implements LeonardApp {
  @override
  LeonardAppConfig build(LeonardAppContext ctx) {
    return LeonardAppConfig(
      extensions: <LeonardExtension>[/* optional: router/riverpod/dio */],
      app: const MyMaterialApp(), // your existing root widget
    );
  }
}
```

`LeonardBinding.run` is debug/profile-only — in release it just runs the app
untouched, so it's safe to leave in. `CoreExtension` (tap, scroll, enter_text,
etc.) is always available; add extension packages only if you want their
extra tools/observations.

## 1. Run the app and get its VM service URI

```bash
flutter run -d <device> --no-devtools > /tmp/app.log 2>&1 &
grep "Dart VM Service on" /tmp/app.log   # -> http://127.0.0.1:PORT/TOKEN/
```

Convert to the websocket form: `ws://127.0.0.1:PORT/TOKEN/ws`. Prefer a
simulator/emulator or a wired device — a desktop window that gets occluded
stops producing semantics (the agent goes blind).

## 2a. Drive autonomously (one goal → done)

Leonard's own loop picks each action with the model you choose:

```bash
dart run leonard_cli:leonard_cli \
  --vm-uri 'ws://127.0.0.1:PORT/TOKEN/ws' \
  --goal 'Sign in with demo@example.com / password, then open Settings and turn on Dark Theme' \
  --model claude \
  --output /tmp/run.jsonl
```

`--model`: `claude` (needs `ANTHROPIC_API_KEY`), `openai` (`OPENAI_API_KEY`),
or `qwen-mlx` (local swift-infer: `SWIFT_INFER_ENDPOINT` +
`SWIFT_INFER_AGENT_TOKEN`). Add `--extensions router,riverpod,dio` if the app
registers them.

## 2b. Drive turn-by-turn (you are the decider)

To choose each action yourself instead of using Leonard's LLM, use the
stateless helper — observe, decide, invoke, repeat:

```bash
DRIVE="dart run leonard_cli:leonard_drive"
$DRIVE tools   --vm-uri "$VM"                         # available tools
$DRIVE observe --vm-uri "$VM"                         # full observation JSON
$DRIVE invoke  --vm-uri "$VM" --tool core.tap --args '{"node_id":12}'
```

Each `observe` returns nodes with `id`, `role`, `label`, `actions`, `rect`,
and — on scrollables — `scroll: {pos, min?, max?}` (you can move ~`max - pos`
further; `pos == max` is the bottom). Target nodes by integer `node_id` from
the current observation. Core tools: `core.tap {node_id}`,
`core.enter_text {node_id, text}`,
`core.scroll {node_id, axis, delta_pixels}`, `core.gesture`,
`core.system_back {}`, `core.inspect_widget {node_id}`, `core.done {reason}`.

## 3. Verify the outcome

Autonomous runs write a trajectory JSONL (`--output`). Check:

- `footer.outcome` — **`done`** = the agent reached the goal (`core.done`);
  `agent_stuck` / `budget_exhausted` = it did not.
- per-turn `executed_action` + `result.ok` (and `result.error` on failure),
  and `observation.core.routeStack` to confirm the target screen.

```bash
grep -oE '"outcome":"[^"]*"' /tmp/run.jsonl | tail -1
```

PASS = `outcome` is `done` AND the goal's success state is visible (right
route, value set, every goal-critical action `ok:true`). On FAIL, capture the
failing `executed_action` + `result.error` + that turn's `observation.core`.

## Gotchas

- Reusing one running app across runs is fine — each connection re-handshakes
  and resets the session. Restart the app only if you changed binding-side
  (`leonard_flutter`) code.
- Empty `core.nodes` (agent blind): foreground the app window, or use a
  simulator/emulator instead of an occluded desktop window.
