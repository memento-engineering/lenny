# Changelog

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
