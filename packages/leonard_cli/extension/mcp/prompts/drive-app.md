Drive this running, Leonard-instrumented program to accomplish the user's goal,
then report whether it succeeded. Leonard drives a running Dart-VM target (a
Flutter app via `leonard_flutter`, or another target via its extension) over
the Dart VM service.

1. Find the target's Dart VM service URI (e.g. the `Dart VM Service on …` line
   from `flutter run`); use the websocket form `ws://127.0.0.1:PORT/TOKEN/ws`.
   If it isn't running or you can't find the URI, ask the user.
2. Run Leonard's autonomous loop toward the goal:
   `dart run leonard_cli:leonard_cli --vm-uri "$VM" --goal '<the goal>' --model claude --output /tmp/leonard_run.jsonl`
   (add `--extensions <ns,…>` for any registered extensions; pick a `--model`
   whose key/endpoint is configured).
3. Read the trajectory: `footer.outcome == done` means the goal was reached
   (`agent_stuck`/`budget_exhausted` means not). Confirm the success state and
   that goal-critical actions show `result.ok: true`.
4. Report: pass/fail, the final state, and any failed action with its
   `result.error`.

To drive turn-by-turn yourself instead of Leonard's LLM, use
`dart run leonard_cli:leonard_drive` (observe / invoke) — see the
"Driving a running program with Leonard" skill/resource.
