# Changelog

## 0.4.3-dev.1

- The bundled leonard-drive agent, drive-with-leonard skill and AGENTS.md
  template read `observation.core.routeLayers` (the routes on screen) in place
  of the deprecated `routeStack` (lenny-kyfdc). `leonard_agent` rises to
  `^0.3.4-dev.1`, which carries the field.

## 0.4.2

Stable promotion of `0.4.2-dev.1` on Nico's promotion call (2026-10-21). One change on top: the runtime `leonard_native` constraint rises from `^0.6.0` to `^0.6.1`, so depending on `leonard_cli` brings in the lenny#198 and lenny#200 backend fixes without a separate pin. The prerelease entry below carries the details.

## 0.4.2-dev.1

Fixes lenny#199: the lenny#160 fix found the native host through the package config, but `leonard_native` was only a dev dependency, so a consumer that depended on `leonard_cli` alone had no `leonard_native` to find and `leonard_drive up` fell back to paths that exist only inside a lenny checkout.

- `leonard_native` (`^0.6.0`) is now a runtime dependency of `leonard_cli`, so
  depending on `leonard_cli` puts it in your package config. You no longer
  need to add `leonard_native` yourself to use `up`'s native path.
- When `up` cannot find the native host and no `--native-host` was passed, it
  exits 64 with an error that says `leonard_native` is missing from the
  program's package config and how to fix it (add `leonard_native` to your
  dependencies, or pass `--native-host`), instead of the generic
  "requires --native-host" message. The working-directory fallback still
  serves development inside a lenny checkout.
- `--summary-json` now carries the run's verdict: `verdict` (`pass`, `fail`
  or `infra`), a one-line `reason`, and `digest`, the last turns as one line
  each (action, result, and the final rationale) under 3000 UTF-8 bytes. A
  run fails only when Leonard drove the app and the goal was not met (budget
  exhausted, the app's VM service gone mid-drive, a golden mismatch); every
  outcome that kept it from judging the app is `infra`, including goldens
  that could not be read or written, which now exit 70 rather than 1
  (lenny#177).
- Add `--gate-exit-codes`: exit 0 pass, 75 infra, 1 fail. 75 is
  `EX_TEMPFAIL`, Gas City's infrastructure code for checks. A usage error
  exits 75 too (lenny#177).

## 0.4.1

Stable promotion of `0.4.1-dev.1` on Nico's promotion call (2026-10-20), on stable `leonard_agent` 0.3.3 and `leonard_native` 0.6.0. The prerelease entry below carries the full list. One change on top:

- `--model claude` now defaults to `claude-sonnet-5-5` (was `claude-sonnet-4-6`), with vision on. On the sample-app goal it finished in 20 s for $0.26, against 35 s and $0.35 for Sonnet 4.6. Pass `--model-id claude-sonnet-4-6` for the old default.

## 0.4.1-dev.1

- Raise the `leonard_agent` floor to `^0.3.3-dev.2`, so a run's usage counts
  model calls its turn budget abandoned (lenny-c55p6).
- Raise the `leonard_native` floor to `^0.6.0-dev.1` (lenny#180 to #183).
- Add `--summary-json <path>`: writes the run's exit code, outcome, turn
  count, duration, trajectory path and usage totals as one JSON file, so CI
  can collect token and cost figures across runs (lenny#178).
- Add `--price-input-per-mtok` / `--price-output-per-mtok`, and the
  `LEONARD_PRICE_INPUT_PER_MTOK` / `LEONARD_PRICE_OUTPUT_PER_MTOK`
  environment pair, to override the built-in price table for the cost
  estimate. The flags outrank the environment.
- Trajectories record per-turn and per-run model usage; the header's
  `harness_version` is now `0.6.0`.
- Require `leonard_agent ^0.3.3-dev.1`.

## 0.4.0

Stable promotion of `0.4.0-dev.1`: the same content, published on the stable rung on Nico's promotion call (2026-10-15), after the Android (Pixel 7a), iOS 26.5 simulator and macOS live suites passed. The prerelease entries below carry the full list.

## 0.4.0-dev.1

- **Breaking — `leonard_drive up`'s native dual path takes `--app-id` instead
  of `--app`.** The native host now attaches to the app `flutter run`
  launched, on iOS and Android alike, instead of being handed the build to
  install; on Android that relaunch would have dropped the Flutter VM-service
  channel. Migration: replace `--app <Runner.app>` with `--app-id <bundle id or
  package>`. A stale `--app` exits 64 with this migration message.
- Requires `leonard_native ^0.5.0-dev.1` and `leonard_agent ^0.3.2-dev.2`.
- Fix: `leonard_drive up` finds the native host through the package config, so
  `--native-host` auto-resolution works outside the lenny repo (lenny#160,
  #166).

## 0.3.1-dev.1

- Add ACP harness inference: drive the loop through a `leonard_acp` harness
  and select it among the registered agent specs.
- Add `--wall-clock-minutes`, the whole-session wall-clock budget (default 15).
- Fix: provider-build errors are caught only for configuration failures.

## 0.3.0

Promotes `0.3.0-rc.1` to stable. The candidate's full change list is under that
entry below.

- **Breaking: requires `leonard_agent ^0.3.0`** and adopts its I/O entrypoint.
  Migration for anything embedding this package's library surface: import
  `package:leonard_agent/leonard_agent_io.dart` for owning connections.
- Fix: `core` tool descriptors are read from the handshake and passed as the
  driver's `coreTools` instead of being projected as bare names, so the model
  sees each core tool's description and input schema (lenny#123).
- Add: `tool/live_macos_smoke.dart` — the live macOS smoke that gates a
  `leonard_flutter` release (lenny#120).

## 0.3.0-rc.1

- **Breaking: requires `leonard_agent ^0.3.0-rc.1`** and adopts its I/O
  entrypoint. Migration for anything embedding this package's library surface:
  import `package:leonard_agent/leonard_agent_io.dart` for owning connections.
- Add observation frame goldens: `leonard_drive` persists observation frames and
  compares them against a stored golden.
- Add the `test-with-leonard` skill router.
- Provider model ids are configurable, and driver token and effort defaults are
  exposed as operator overrides.
- The portable pure-Dart mutation runner ships with its Flutter delegate; dry
  output counts as sizing evidence, and zero uncovered mutation lines is accepted
  rather than failed.
- Self-drive: completion is gated on observed timeline evidence, a model must be
  selected before Start, diagnostic evidence survives an observation failure, and
  panel session markers are durable.
- Raise the sibling floors to the published wave: `leonard_contract ^0.2.2`,
  `leonard_host ^0.2.2`, `leonard_native ^0.4.1`.

## 0.2.1

- `install --copilot` now overlays `.github/agents/` — the location GitHub
  Copilot (CLI, coding agent, VS Code) actually scans — instead of the retired
  repo-root `agents/`+`skills/` plugin layout. Skills need no overlay:
  `.agents/skills/` is a first-class Copilot skill location, and
  `gh skill install memento-engineering/lenny drive-with-leonard` installs
  straight from this package's vendored assets.
- The vended `leonard-drive` agent's tools list carries both harness
  vocabularies (`Bash, Read, execute`), so the same file drives Claude Code
  and Copilot unchanged.

## 0.2.0

- Breaking: `leonard_drive` speaks the `ext.leonard.*` VM-service namespace
  (protocol version 2). Target apps must run `leonard_*` 0.2.0 — a 0.1.x app
  still registers `ext.exploration.*` and will not answer the handshake.

## 0.1.5

- Bundled `AGENTS.md` template documents the perception `identifier` / `value`
  fields and the addressing-vs-inference guidance, matching `leonard_agent`
  0.1.5 (`kDefaultAgentsMd`); depends on `leonard_agent ^0.1.5`.

## 0.1.4

- `leonard_drive up` gains a native dual path: boot a Flutter target AND the
  `leonard_native` host against ONE shared device, expose both VM-service
  endpoints (`DualLaunchHandle{flutterWsUri, nativeEndpoint, deviceId}`), and
  tear both down via a single `--pid-file`. The single-target path is
  unchanged.
- New `drive-dual` subcommand (`tools` / `observe` / `invoke`) drives a
  multi-host `MultiHostSession` over both endpoints — merged manifest, merged
  observation, namespace-routed tool calls — so an external brain can perceive
  and drive a Flutter app and the native channel together.

## 0.1.3

- `leonard_drive tools` now prints a `capabilities` array next to `namespaces`.
  It surfaces reachable host features that are not namespaced tools — notably
  `screenshot` (use the `screenshot` subcommand), which is absent from
  `namespaces` by design. Stops the recurring "the manifest has no screenshot,
  so there is no screenshot capability" mistake. Requires `leonard_agent`
  `^0.1.3` (the handshake parse that decodes `capabilities`).
- `leonard_drive` gains `up` / `down` lifecycle subcommands that erase the
  manual boot-grep-convert dance. `up --runner flutter -d <device> -t <entry>`
  (or `--runner dart -t <entry>` for a pure-Dart target) boots the app,
  discovers the VM-service URI, prints it machine-readably
  (`{event:"vm_service_ready", ws_uri, …}` plus optional `--uri-file` /
  `--pid-file`), then HOLDS the process alive (teeing its log to stderr) until
  a signal or `down`. No model, no goal, no loop — the external brain attaches
  stateless `observe`/`invoke`/`screenshot` calls to `ws_uri`. `down
  --pid-file <p>` stops a held target. New shared `launcher.dart` primitive
  (spawn + scrape + hold + teardown) backs it.
- `leonard_cli` gains `--launch` for the autonomous loop: instead of a
  caller-supplied `--vm-uri`, boot the target (`--runner flutter -d <device>
  -t <entry>`, or `--runner dart -t <entry>`) via the shared launcher, drive
  the discovered URI with lenny's own LLM toward `--goal`, then tear the
  target down. `--launch` and `--vm-uri` are mutually exclusive (and the
  boot-only flags error without `--launch`) — no dual-mode interface.

## 0.1.2

- `leonard_drive` gains a `screenshot` subcommand: capture a still and write the
  PNG to `--out path.png` (decodes `core.screenshot`; prints
  width/height/device-pixel-ratio). Just pixels — no settle, no golden compare.

## 0.1.1

- Provider construction moves to the `DartanticModelProvider` seam (the agent's
  unified backend factory).
- Ship consumer coding-agent assets plus an `install` command, with
  harness-specific overlays (`--claude` / `--copilot` / `--all`). The bundled
  assets are target-agnostic (Dart-VM, not Flutter-specific).

## 0.1.0

Initial release.
