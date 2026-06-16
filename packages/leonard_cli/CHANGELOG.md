# Changelog

## 0.1.1

- Provider construction moves to the `DartanticModelProvider` seam (the agent's
  unified backend factory).
- Ship consumer coding-agent assets plus an `install` command, with
  harness-specific overlays (`--claude` / `--copilot` / `--all`). The bundled
  assets are target-agnostic (Dart-VM, not Flutter-specific).

## 0.1.0

Initial release.
