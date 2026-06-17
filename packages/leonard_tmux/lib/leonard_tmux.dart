/// A pure-Dart, process-backed Leonard *contract* extension for tmux.
///
/// [TmuxExtension] is a stateful, self-watching `LeonardExtension` (the same
/// shape as the Flutter reference extensions): it subscribes to a genesis_tmux
/// observation source and keeps a live snapshot current, projecting it into a
/// genesis_perception tree that the host serializes into the `tmux`
/// observation fragment, and exposes `send_keys` / `new_session` tools. Unlike
/// the Flutter extensions it observes an external process rather than the host
/// app — so it is pure Dart and uses no Flutter. Host it over the VM service
/// with `leonard_host`'s `ExplorationHost` to drive a tmux server live.
library;

export 'src/tmux_extension.dart' show TmuxExtension;
export 'src/tmux_observation.dart'
    show TmuxObservation, TmuxPaneSnapshot, gatherTmuxObservation;
export 'src/tmux_perception.dart' show TmuxPerception;
