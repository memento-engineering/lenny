/// The perception-native projection: a [NativeSnapshot] expressed as a
/// genesis_perception `Node`/`Field` tree, mirroring the Flutter core fragment
/// (which carries the semantics record-list as a single `Field`).
library;

import 'package:genesis_perception/genesis_perception.dart';

import 'native_snapshot.dart';

/// Builds the `native` perception fragment from a cached [snapshot].
///
/// The per-node record list is carried as **one** `Field('elements', ...)`,
/// NOT a Node-per-element subtree — so the wire shape is flat and sidesteps
/// sibling-name collisions (anonymous Auth0 fields can share empty a11y-ids).
/// This mirrors Flutter's `Field('semantics', List<Map>)`.
class NativePerception extends StatelessPerception {
  /// Projects [snapshot] into a measurement tree.
  const NativePerception(this.snapshot, {super.key});

  /// The snapshot being projected.
  final NativeSnapshot snapshot;

  @override
  Seed build(PerceptionContext ctx) => Node(
    'native',
    children: <Seed>[
      Field('platform', snapshot.platform),
      Field('node_count', snapshot.nodes.length),
      Field('elements', <Map<String, Object?>>[
        for (final NativeNode n in snapshot.nodes) n.toRecord(),
      ]),
    ],
  );
}
