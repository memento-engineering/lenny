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
`qwen-mlx` (local swift-infer: `SWIFT_INFER_ENDPOINT`,
`SWIFT_INFER_AGENT_TOKEN`, and `SWIFT_INFER_MODEL` — the model id, defaulting
to `qwen3.6-35b-a3b-8bit`). `--model-id <id>` pins the exact model id for the
chosen tier and outranks `SWIFT_INFER_MODEL`. Add `--extensions <ns,…>` for any
registered extensions (e.g. `router,riverpod,dio`, or `tmux`).

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

## Tool reference (turn-by-turn driving)

For manual driving (via `leonard_drive`) or scripting a device:

- Target nodes by **integer** `node_id` from the CURRENT observation whose
  `actions` permit it. Core tools + required args: `core.tap {node_id}`,
  `core.long_press {node_id}`, `core.enter_text {node_id, text}`,
  `core.scroll {node_id, axis:"vertical"|"horizontal", delta_pixels}`
  (read the node's `scroll` — move ~`max - pos` further; `pos == max` = at the
  bottom), `core.gesture {node_id, kind}`, `core.inspect_widget {node_id}`,
  `core.wait {seconds}`, `core.system_back {}`, `core.done {reason}`.
- **Never repeat an action that just failed** — read `result.error` (it names
  the bad field) and change something. One `invoke` per turn; `observe`
  between actions.
- Trim observe output with jq to keep context small, e.g. only actionable
  nodes:
  `... observe ... | jq -c '{route:.observation.core.routeStack, nodes:[.observation.core.nodes|to_entries[].value|select((.actions//[])|length>0)|{id,role,label,actions,state,scroll}]}'`

## Verify

`--output` trajectory: `footer.outcome` is one of three wire values —
`done` = goal reached; `budget_exhausted` = ran out of turns before reaching
it; `harness_error` = the run itself broke (the footer's `harness_error`
field carries the cause — do not read a harness failure as "goal not
reached"). Check per-turn `result.ok` and the target's route/state.

```bash
grep -oE '"outcome":"[^"]*"' /tmp/run.jsonl | tail -1
```

## Non-Flutter targets

The extension/perception model is target-agnostic, and the **pure-Dart live
host ships today**: `leonard_host` (`ExplorationHost`) serves any Dart-VM
target's extensions over the VM service — no Flutter anywhere in the stack.
`leonard_native`'s host runner (`bin/leonard_native_host.dart`) is a shipping
example: it hosts the `native` extension and is driven live by
`leonard_cli`/`leonard_drive` exactly like a Flutter app (proven end-to-end in
its `native_host_e2e_test.dart`). Extensions can still be used as a plain
library (`extension.observe()` / `extension.executeAction(...)` — see
`leonard_tmux/example/main.dart`) when you don't need live driving.
