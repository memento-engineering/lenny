/// A pure-Dart, process-backed Leonard extension for tmux.
///
/// [TmuxExtension] projects a genesis_tmux client's sessions, panes, and recent
/// output into a genesis_perception tree, serializes it into a Leonard
/// `ExtensionFragment` under the `tmux` namespace, and exposes `tmux.send_keys`
/// / `tmux.new_session` tools dispatched to the underlying tmux verbs. Unlike
/// the Flutter reference extensions, it observes an external process rather than
/// the host app — so it is pure Dart and uses no Flutter.
library;

export 'src/tmux_extension.dart' show TmuxExtension;
export 'src/tmux_observation.dart'
    show TmuxObservation, TmuxPaneSnapshot, gatherTmuxObservation;
export 'src/tmux_perception.dart' show TmuxPerception;
