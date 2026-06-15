library;

import 'package:genesis_perception/genesis_perception.dart';

import 'internals.dart';

/// Perception-native view of the Riverpod observation fragment.
///
/// Reads the SAME [ExplorationProviderObserver] the plugin holds, so the
/// derived lists are the plugin's sole observation surface. Mirrors
/// `DioPerception`.
///
/// Note: this emits the FULL tree (no in-fragment truncation, no `truncated`
/// key). The binding's downstream `encodeWithBudget` is the single
/// truncation authority.
///
/// It does NOT flush the observer ring: `buildPerception()` takes no turn
/// argument. The plugin's `prepareForObservation()` hook performs
/// `flushPendingAt` first (called by the binding before build), so this
/// build reads the already-drained ring.
class RiverpodPerception extends StatelessPerception {
  const RiverpodPerception(this._o);

  final ExplorationProviderObserver _o;

  @override
  Seed build(PerceptionContext ctx) {
    final List<String> ids = _o.live.keys.toList(growable: false);
    final List<Map<String, Object?>> ch = _o
        .recentChanges()
        .map((c) => c.toJson())
        .toList(growable: false);
    return Node('riverpod', children: <Seed>[
      Field('invalidatable_providers', ids),
      Field('recent_state_changes', ch),
    ]);
  }
}
