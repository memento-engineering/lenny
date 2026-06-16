Drive this running, Leonard-instrumented Flutter app to accomplish the user's
goal, then report whether it succeeded.

1. Find the app's Dart VM service URI (the `Dart VM Service on …` line from
   `flutter run`); use the websocket form `ws://127.0.0.1:PORT/TOKEN/ws`. If
   the app isn't running or you can't find the URI, ask the user.
2. Run Leonard's autonomous loop toward the goal:
   `dart run leonard_cli:leonard_cli --vm-uri "$VM" --goal '<the goal>' --model claude --output /tmp/leonard_run.jsonl`
   (use `--extensions router,riverpod,dio` if the app registers them; pick a
   `--model` whose API key / endpoint is configured).
3. Read the trajectory: `footer.outcome == done` means the goal was reached
   (`agent_stuck`/`budget_exhausted` means it wasn't). Confirm the success
   state in the last turn's `observation.core.routeStack` and that
   goal-critical actions show `result.ok: true`.
4. Report: pass/fail, the final screen/state, and any failed action with its
   `result.error`.

To drive turn-by-turn yourself instead of using Leonard's LLM, use
`dart run leonard_cli:leonard_drive` (observe / invoke) — see the
"Driving a Flutter app with Leonard" resource.
