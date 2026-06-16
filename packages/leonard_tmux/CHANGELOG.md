# Changelog

## 0.1.0

- Initial release: a pure-Dart, process-backed Leonard extension for tmux.
  Projects a `genesis_tmux` client into a `genesis_perception` tree
  (`TmuxPerception`), serializes it into a `leonard_agent` `ExtensionFragment`
  under the `tmux` namespace (`TmuxExtension.observe`), and exposes
  `tmux.send_keys` / `tmux.new_session` tools (`TmuxExtension.executeAction`).
  Includes a live `example/` that drives a real tmux server on an isolated
  socket.

  Pre-1.0 and experimental; APIs may change before 1.0.
