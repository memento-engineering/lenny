# Changelog

## 0.2.0

- Breaking: requires `leonard_contract`/`leonard_agent`/`leonard_host` 0.2.0
  (the `ext.leonard.*` namespace wave). No API changes in this package.

## 0.1.1

- Migrated to the unified `leonard_contract`: `TmuxExtension` is now a
  `LeonardExtension` with `PerceptionExtension`. It watches the tmux server
  out-of-band (a `genesis_tmux` `PollObservationSource`) and `buildPerception()`
  reads a live snapshot **synchronously**; the async
  `observe()` / `executeAction()` pull surface is removed. Now depends on
  `leonard_contract` instead of `leonard_agent`. Adds
  `example/tmux_vm_host.dart` (an `ExplorationHost` runner) and a live
  VM-service end-to-end test.

## 0.1.0

- Initial release: a pure-Dart, process-backed Leonard extension for tmux.
  Projects a `genesis_tmux` client into a `genesis_perception` tree
  (`TmuxPerception`), serializes it into a `leonard_agent` `ExtensionFragment`
  under the `tmux` namespace (`TmuxExtension.observe`), and exposes
  `tmux.send_keys` / `tmux.new_session` tools (`TmuxExtension.executeAction`).
  Includes a live `example/` that drives a real tmux server on an isolated
  socket.

  Pre-1.0 and experimental; APIs may change before 1.0.
