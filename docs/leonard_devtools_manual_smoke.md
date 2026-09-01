# Smoke — leonard_devtools panel

The provider/session UI half of the former lenny-ch8 manual smoke (old steps
4-9) is automated by
[`packages/leonard_cli/scenarios/leonard_devtools_panel.md`](../packages/leonard_cli/scenarios/leonard_devtools_panel.md).
`tool/run_panel_selfdrive_scenario.sh` starts the two-target
[`tool/run_panel_selfdrive.sh`](../tool/run_panel_selfdrive.sh) harness, attaches
the outer `leonard_cli` to the panel's debug DWDS connection, and has the panel
drive the real `sample_app` connection.

The scenario fills swift-infer provider settings from environment placeholders,
requires `OK (N models)`, enters the small goal, presses Start, opens Timeline,
opens a rendered `TurnRecord` and checks its Proposed action tool, then verifies
the Start button is enabled after Stop or natural SessionEnded. Its receipt
records the outer trajectory path, inner row index/tool, prompt-form state, and
a scan of captured trajectory/driver/harness output.

## Run the automated operator smoke

This is operator-invoked only: it needs Chrome, a sample-app device, and a live
provider. It is not a CI lane.

```sh
export SWIFT_INFER_ENDPOINT='https://your-swift-infer-host'
export SWIFT_INFER_AGENT_TOKEN='your-runtime-token'
export PANEL_SELFDRIVE_MODEL_ID='qwen3.6-35b-a3b-8bit' # optional default
./tool/run_panel_selfdrive_scenario.sh macos
```

The bearer token is read only from the environment. The committed scenario
contains `${SWIFT_INFER_AGENT_TOKEN}`, and the outer trajectory retains that
placeholder while the action boundary supplies the runtime value to the panel.

## Manual remainder

1. Build the shipped extension with `tool/build_devtools_extension.sh` and open
   the real Leonard extension in Dart DevTools against a debug `sample_app`.
   This remains a release-bundle packaging check: the self-drive scenario uses
   `packages/leonard_devtools/dev/selfdrive_main.dart` under `flutter run`
   because the shipped dart2js release bundle is unattachable.
2. In Chrome DevTools, search the console after the automated run for the actual
   bearer-token/API-key values. The driver can scan its own trajectory and
   process logs, but it cannot observe the browser console. PASS requires no
   credential value there; append `DEVTOOLS_CONSOLE_SECRET_SCAN=clean` beside
   the scenario receipt in bead `lenny-f7nx.4` notes.

Provider-shape parity checks remain in
[`packages/leonard_devtools/MANUAL_TESTS.md`](../packages/leonard_devtools/MANUAL_TESTS.md).
