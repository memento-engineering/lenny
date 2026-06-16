/// A point-in-time snapshot of a tmux server, gathered through the Tier-1
/// verbs — the raw material the perception projection turns into a measurement.
library;

import 'package:genesis_tmux/genesis_tmux.dart';
import 'package:meta/meta.dart';

/// One pane plus a bounded tail of its recent output.
@immutable
class TmuxPaneSnapshot {
  /// Pairs pane metadata [info] with its captured [recentOutput].
  const TmuxPaneSnapshot({required this.info, required this.recentOutput});

  /// The pane's metadata (id, window, pid, command, liveness).
  final PaneInfo info;

  /// The captured tail of the pane's transcript (empty for a dead pane).
  final String recentOutput;
}

/// Everything observed about a tmux server in one gather pass.
@immutable
class TmuxObservation {
  /// Records the [socketLabel], the [sessions], and per-pane [panes] snapshots.
  const TmuxObservation({
    required this.socketLabel,
    required this.sessions,
    required this.panes,
  });

  /// A human-readable label for the socket this was gathered from.
  final String socketLabel;

  /// Every session on the socket.
  final List<SessionInfo> sessions;

  /// Every pane on the socket, with its recent output.
  final List<TmuxPaneSnapshot> panes;
}

/// Gathers a [TmuxObservation] from [client]: lists sessions and panes, then
/// captures the last [captureLines] of each live pane. One async pass; the
/// caller decides cadence (every agent turn, on a tick, …).
Future<TmuxObservation> gatherTmuxObservation(
  TmuxClient client, {
  int captureLines = 40,
}) async {
  final sessions = await client.listSessions();
  final panes = await client.listPanes();
  final snapshots = <TmuxPaneSnapshot>[];
  for (final pane in panes) {
    final output = pane.dead
        ? ''
        : await client.capturePane(pane.id, lines: captureLines);
    snapshots.add(TmuxPaneSnapshot(info: pane, recentOutput: output));
  }
  return TmuxObservation(
    socketLabel: client.socket.label,
    sessions: sessions,
    panes: snapshots,
  );
}
