# Driving a Flutter app with Leonard

This app depends on `leonard_flutter`, so it can be driven by an LLM: Leonard
observes the running app's semantics tree and calls tools (tap, enter_text,
scroll, …) over the Dart VM service to accomplish a goal. Use this to verify
real UI flows end-to-end (navigation, multi-screen, live state).

## 1. Instrument `main()` (once)

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

`LeonardBinding.run` is debug/profile-only (a no-op passthrough in release), so
it's safe to leave in. `CoreExtension` (tap/scroll/enter_text/…) is always on.

## 2. Run and connect

```bash
flutter run -d <device> --no-devtools > /tmp/app.log 2>&1 &
grep "Dart VM Service on" /tmp/app.log   # http://127.0.0.1:PORT/TOKEN/
# use the websocket form: ws://127.0.0.1:PORT/TOKEN/ws
```

## 3. Drive

Autonomous (Leonard's LLM picks each action):

```bash
dart run leonard_cli:leonard_cli \
  --vm-uri 'ws://127.0.0.1:PORT/TOKEN/ws' \
  --goal '<plain-English goal>' --model claude --output /tmp/run.jsonl
```

Turn-by-turn (you decide each action):

```bash
dart run leonard_cli:leonard_drive observe --vm-uri "$VM"
dart run leonard_cli:leonard_drive invoke  --vm-uri "$VM" --tool core.tap --args '{"node_id":12}'
```

Observations expose each node's `id`, `role`, `label`, `actions`, `rect`, and —
on scrollables — `scroll: {pos, min?, max?}` (move ~`max - pos` further;
`pos == max` is the bottom).

## 4. Verify

`--output` trajectory: `footer.outcome == done` means the goal was reached.
Check per-turn `result.ok` and `observation.core.routeStack` for the target
screen.

For a turnkey local setup, run `dart run leonard_cli:install` — it drops a
`drive-flutter-app` skill and `leonard-driver`/`leonard-pilot` agents into your
repo's `.agents/` for your coding agent.
