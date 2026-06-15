/// Wire path for the spike5 catalog.
///
/// REUSED from spike3 (unchanged, via path dep): the A2UI v0.9 envelope and
/// component parsing — `SurfaceUpdate.fromJson` and `ComponentSpec`.
///
/// MINIMAL FORK from spike3: [buildPerceptionTree] below is a line-for-line
/// copy of spike3's wire.dart function, re-bound to SPIKE5's generated
/// registry. The fork is forced: spike3's wire.dart hardcodes
/// `import 'generated/registry.g.dart'` and calls the free function
/// `buildComponent` directly — the tree builder is not parameterized over
/// the registry, so it cannot be pointed at another catalog's factories.
/// Genesis A2/A6 feedback (see NOTES.md): either generate the tree builder
/// per catalog alongside the registry, or make it take the component
/// factory as an argument.
library;

import 'package:perception/perception.dart';
import 'package:spike3_schema_roundtrip/src/wire.dart'
    show ComponentSpec, SurfaceUpdate;

import 'generated/registry.g.dart';

/// Flat list -> Perception tree, via SPIKE5's GENERATED registry only.
///
/// Rejects: duplicate id, unknown rootId, dangling childId, cycles,
/// and (via the registry) unknown types / bad props / children on leaves.
Perception buildPerceptionTree(SurfaceUpdate update) {
  final byId = <String, ComponentSpec>{};
  for (final c in update.components) {
    if (byId.containsKey(c.id)) {
      throw StateError(
        'duplicate component id "${c.id}" in surface "${update.surfaceId}"',
      );
    }
    byId[c.id] = c;
  }
  if (!byId.containsKey(update.rootId)) {
    throw StateError(
      'unknown rootId "${update.rootId}" — no component with that id in '
      'surface "${update.surfaceId}"',
    );
  }

  final visiting = <String>{};
  Perception build(String id) {
    final spec = byId[id];
    if (spec == null) {
      throw StateError(
        'dangling childId "$id" — no component with that id in '
        'surface "${update.surfaceId}"',
      );
    }
    if (!visiting.add(id)) {
      throw StateError(
        'cycle detected through component id "$id" in '
        'surface "${update.surfaceId}"',
      );
    }
    final children = [for (final childId in spec.childIds) build(childId)];
    visiting.remove(id);
    // Component id becomes the Perception key — the reconciliation identity.
    return buildComponent(spec.type, spec.props, children, spec.id);
  }

  return build(update.rootId);
}

/// Convenience: decoded JSON envelope -> Perception tree.
Perception perceptionFromMessage(Map<String, Object?> message) =>
    buildPerceptionTree(SurfaceUpdate.fromJson(message));
