# Changelog

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
