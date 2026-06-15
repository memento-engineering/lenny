# Runbook — Live-device E2E dogfood run

**Purpose:** drive Leonard against the **real sample app on a real device**
and judge whether it completes a goal end-to-end (observe → decide → act → `core.done`). This is
the manual, reproducible version of the 2026-05-31 milestone run (tap "Sign In" → login→home →
`core.done`). Use it to verify a freshly-merged fix works on-device, or as the acceptance step at
the end of a `/harden` cycle.

> **Not the same as `melos run test:e2e`.** That is the *automated* dogfood e2e
> (`packages/leonard_agent/test/e2e/dogfood_e2e_test.dart`): fixture-driven, runs against a
> **swift-infer** endpoint, no device, env-gated on `SWIFT_INFER_ENDPOINT`/`SWIFT_INFER_AGENT_TOKEN`,
> and self-skips when unset. It's a CI/regression check of the provider+harness, not a live drive of
> the app. See §7. **This runbook is the on-device drive.**

---

## 0. Prerequisites (once)

- **A wired iOS device** (known good: iPad mini, id `00008110-001651523CE3801E`). It must show in
  `flutter devices` **without** `(wireless)`. If it shows wireless while plugged in, uncheck
  **"Connect via network"** in Xcode → Window → Devices and Simulators (wireless VM-service
  discovery hangs ~75 s and fails). macOS desktop also works but throttles semantics when the window
  is occluded (see §6) — prefer the wired device.
- `~/.lenny-dogfood.env` exists and exports `ANTHROPIC_API_KEY` (scoped here, **not** `~/.zshenv`, so
  it bills pay-as-you-go API) plus the swift-infer tokens. It self-skips cleanly if absent.
- Flutter ≥ 3.44, Melos bootstrapped, signing team `<APPLE_TEAM_ID>`, bundle `com.nicospencer.sampleApp`.
- The app is built **from a branch/worktree that carries the fixes you want to test.** For fixes
  already on `main` (e.g. `lenny-whn` semantics, `lenny-c94` enter_text, `lenny-22f` DPR), build
  from `main`. The app supplies the binding; the agent CLI (run from `main`) supplies the agent/tools.

---

## 1. Confirm the device is wired

```bash
flutter devices
# Expect the target device listed WITHOUT "(wireless)".
```

## 2. Launch the app (stays attached across runs)

```bash
cd packages/leonard_flutter/example/sample_app
flutter run -d 00008110-001651523CE3801E --no-devtools > /tmp/lenny_ipad.log 2>&1 &
# Wait ~60-90s for the build, then grab the VM service URI:
grep "Dart VM Service on" /tmp/lenny_ipad.log
#  -> "A Dart VM Service on … is available at: http://127.0.0.1:PORT/TOKEN/"
```

Convert the printed `http://127.0.0.1:PORT/TOKEN/` to the websocket form:
`ws://127.0.0.1:PORT/TOKEN/ws`.

The app **stays attached** — reuse it across many agent runs; only the agent CLI recompiles
(~10-15 s). There is **no per-iteration app rebuild** unless you change binding-side
(`leonard_flutter`) code.

## 3. Run the agent against a goal

```bash
cd packages/leonard_cli
source ~/.lenny-dogfood.env
dart run bin/leonard_cli.dart \
  --vm-uri 'ws://127.0.0.1:PORT/TOKEN/ws' \
  --goal '<goal — see §5 scenarios>' \
  --extensions router,riverpod,dio \
  --model claude \
  --policy action-relative
```

Flags (from `cli_args.dart`): `--vm-uri` (required, ws://), `--goal` (or pipe via stdin),
`--model` (`claude`|`openai`|`qwen-mlx`, default `claude`), `--policy`
(`action-relative`|`frame-stable`|`idle`, default `action-relative`), `--extensions`
(comma-separated namespaces), `--output` (default `./trajectories/<UTC-timestamp>.jsonl`).
A completable goal finishes in a handful of turns (~40-60 s). Background it and let it run.

## 4. Inspect the trajectory

Newest file in `packages/leonard_cli/trajectories/*.jsonl`. Read, per turn:

- `footer.outcome` — **`done` = goal completed** (the agent called `core.done`).
  `agent_stuck` / `budget_exhausted` = did not complete.
- `observation.core` — `nodes` (count; must be > 0 or the agent is blind — see §6),
  `routeStack`, `errors`.
- `observation.extensions` — per-extension fragments (router `current_route_name`/`stack`, riverpod
  `invalidatable_providers`, …).
- `proposed_action` / `executed_action` + `result.ok` / `result.error`, and `validation.reason`.
- The `[model]` stderr lines (`http=`, `stop_reason=`, `ok=`) — per-call API health. A masked
  `SchemaRejection: no tool_use block` with `http=400` means the **request body** was rejected
  (not the model misbehaving).

## 5. Pass / fail criteria

**PASS** = `footer.outcome == done` AND the goal's success state is reached (e.g. `routeStack`
shows `home`), AND every action the goal required shows `result.ok:true`.

**FAIL** = `agent_stuck` / `budget_exhausted`, or the goal-critical action returned `result.ok:false`,
or the agent looped without progressing. Capture: the failing `executed_action` + `result.error`,
the turn's `observation.core`, and the `[model]` line. That capture is the seed for the next
`/harden` root-cause.

### Scenario catalog (templates)

| Scenario | Goal string | Exercises | Pass signal |
|---|---|---|---|
| **Smoke (tap-only)** — the milestone | `Sign in to the app` | `core.tap` on a pre-filled login | `core.tap` Sign In ok → routeStack `home` → `done` |
| **Text entry** — verifies `lenny-c94`/`whn`/`22f` | `Log in by typing the email and password, then sign in` (use the app's valid creds) | `core.enter_text` into the `Semantics(textField:true)` wrapper nodes → tap | each `core.enter_text` `result.ok:true` (controller value set) → tap Sign In → `home` → `done` |
| **Navigation** (blocked) | `Open Settings` | `router.navigate` / `core.tap` | **known-broken for go_router — see lenny-18q** |

> **Text-entry caveat:** the sample login fields may be **pre-filled** with valid creds, so a model
> may tap Sign In without typing. To genuinely exercise `enter_text`, phrase the goal to require
> changing a field (e.g. "change the email to `user@example.com`, then sign in") and verify the
> trajectory shows an `executed_action` of `core.enter_text` with `result.ok:true`. The on-device
> proof of `lenny-c94` is that `enter_text` against the wrapper node now succeeds (it used to return
> `target_unreachable: … does not advertise SemanticsAction.setText`).

## 6. Reset / teardown / troubleshooting

- **Reset to login between runs:** if the app is on `home` from a prior run, have the agent (or a
  probe) tap the **"Log Out"** button (it advertises `[tap]`); the app returns to the login screen.
  No rebuild needed.
- **Stop cleanly:** `pkill -f "flutter run -d 00008110"` and
  `pkill -f "iproxy .* --udid 00008110-001651523CE3801E"`.
- **`core.nodes` empty (agent blind):** on macOS desktop this is usually an **occluded window** —
  foreground it (`osascript -e 'tell application "System Events" to set frontmost of (first process
  whose name contains "sample") to true'`) or use the wired iOS device (no occlusion). On a fresh
  app the first capture used to race; that's fixed by `captureAsync` (`lenny-whn`, merged).
- **A `core.*` tool vanished mid-run / `oneOf violated`:** the `core` plugin was auto-disabled after
  3 observation failures (fixed: `core` is exempt — `lenny-4jn`, merged). If it recurs, check
  `loop_driver._accountPluginStrikes`.
- **Coordinate-fallback taps miss on a Retina device:** physical-vs-logical px bug, fixed by
  `lenny-22f` (merged). If a synthesized tap/scroll lands off-target, re-check `globalRectOf`.
- **Reuse the device app; only recompile the CLI.** Rebuild the app **only** when you change
  `leonard_flutter` (binding-side) code.

## 7. Automated variant (CI / no device)

```bash
export SWIFT_INFER_ENDPOINT=...   # base URL
export SWIFT_INFER_AGENT_TOKEN=... # bearer
melos run test:e2e
# == dart test packages/leonard_agent/test/e2e/dogfood_e2e_test.dart
```

Fixture-driven, three canonical scenarios (`happyPathDarkMode`, `unknownToolNameSurvives`,
`emptyObservationDoesNotCrash`) against swift-infer. Self-skips when the env vars are unset, so a
bare `melos run test` won't hang. On failure it prints `tracePath` so the swift-infer `request_id`
can be cross-referenced via the `debug-inference` skill. Ad-hoc prompt tuning:
`packages/leonard_agent/tool/agent_dogfood.dart`.

---

## Provenance / template note

This runbook generalizes the **2026-05-31 milestone** (Leonard completed a goal on the wired
iPad: tap Sign In → login→home → `core.done`) and the `/harden` dogfood loop
(`.claude/skills/harden/`). The text-entry scenario in §5 is the next thing to verify on-device now
that `lenny-c94` (widget-tree `enter_text`), `lenny-whn` (semantics `captureAsync`), and `lenny-22f`
(DPR coordinate fix) are merged to `main` (commits `2c95c8a`, `ac4f82e`, `053bce5`).

**Related:** `/harden <integration>` (the fix-finding loop), `docs/how-leonard-works.md`,
`docs/CONTINUATION-text-entry-2026-05-31.md` (now largely closed out — its three beads are merged).
