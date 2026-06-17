# Changelog

## 0.1.3

- `leonard_drive tools` now prints a `capabilities` array next to `namespaces`.
  It surfaces reachable host features that are not namespaced tools — notably
  `screenshot` (use the `screenshot` subcommand), which is absent from
  `namespaces` by design. Stops the recurring "the manifest has no screenshot,
  so there is no screenshot capability" mistake. Requires `leonard_agent`
  `^0.1.3` (the handshake parse that decodes `capabilities`).

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
