/// The perception-native projection: a [TmuxObservation] expressed as a
/// genesis_perception `Node`/`Field` tree, exactly as the Flutter reference
/// extensions (router, dio) project their subsystems — only here the subject
/// is an external tmux server rather than the host app.
library;

import 'package:genesis_perception/genesis_perception.dart';

import 'tmux_observation.dart';

/// Builds the `tmux` perception fragment from a gathered [observation].
///
/// Sibling node names are the tmux ids (`%0`, `$1`) / session names, which are
/// unique per server, so the serialized map keys never collide.
class TmuxPerception extends StatelessPerception {
  /// Projects [observation] into a measurement tree.
  const TmuxPerception(this.observation, {super.key});

  /// The snapshot being projected.
  final TmuxObservation observation;

  @override
  Component build(PerceptionContext ctx) {
    return Node(
      'tmux',
      children: <Component>[
        Field('socket', observation.socketLabel),
        Field('session_count', observation.sessions.length),
        Field('pane_count', observation.panes.length),
        Node(
          'sessions',
          children: <Component>[
            for (final s in observation.sessions)
              Node(
                s.name,
                children: <Component>[
                  Field('id', s.id),
                  Field('attached', s.attached),
                  Field('windows', s.windows),
                ],
              ),
          ],
        ),
        Node(
          'panes',
          children: <Component>[
            for (final p in observation.panes)
              Node(
                p.info.id,
                children: <Component>[
                  Field('window', p.info.windowId),
                  Field('command', p.info.currentCommand),
                  Field('pid', p.info.pid),
                  Field('dead', p.info.dead),
                  Field('recent_output', p.recentOutput),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
