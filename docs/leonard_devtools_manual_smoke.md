# Manual smoke — leonard_devtools panel

Steps a human runs by hand for things automated tests cannot reach
(real network endpoints, real model providers, real binding traffic).

See also: [`../MANUAL_TESTS.md`](../MANUAL_TESTS.md) for the
provider-shape parity checklists (Anthropic, swift-infer).

## End-to-end session.run smoke (lenny-ch8)

Goal: with a configured provider and a connected `sample_app`, pressing
**Start** in the prompt panel runs at least one turn end-to-end and at
least one `TurnRecord` is rendered in the Timeline tab.

Steps:

1. Build the extension: `tool/build_devtools_extension.sh` (or
   equivalent — see `lenny-1l8`).
2. Launch `packages/sample_app` (`flutter run -d <device>`); it must
   call `LeonardBinding.ensureInitialized()` in `main()`.
3. Open DevTools → **Leonard** tab.
4. In the **Prompt** panel:
   - Provider: `swift-infer` (or any configured provider).
   - Endpoint / bearer token: a reachable instance.
   - Model id: any model the provider lists (e.g.
     `qwen3.6-35b-a3b-8bit`).
5. Click **Test connection** — expect "OK (N models)".
6. Enter a small goal (e.g. "tap the first ListTile and report what
   you see").
7. Click **Start**. Wait for the first turn to land.
8. Switch to the **Timeline** tab. Verify at least one `TurnRecord`
   row appears with a non-empty `proposed_action.tool` (e.g.
   `core.tap`).
9. Either press **Stop**, or wait for `SessionEnded` — the form must
   re-enable (the Start button returns) when the loop exits.

PASS criteria:

- At least one `TurnRecord` rendered in the Timeline tab within the
  first turn.
- No bearer token / api key appears in the DevTools console.
- After the loop terminates (either via Stop or natural exit), the
  prompt form re-enables.

Failure surfaces tracked separately:

- A configured provider but `Start` does nothing (or never reaches the
  binding): controller wiring regression — see
  `prompt_panel_controller_test.dart` and
  `broadcast_trajectory_sink_test.dart`.
- Timeline tab stays empty during a confirmed run: shell-level
  trajectory-bridge regression — see the
  `TimelinePanelMount.trajectoryStream rebuilds …` test in
  `shell_test.dart`.
