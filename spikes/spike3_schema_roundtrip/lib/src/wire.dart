/// A2UI v0.9-shaped wire message + deserializer.
///
/// Wire shape mirrors the real A2UI v0.9 `updateComponents` message
/// (https://a2ui.org/specification/v0.9-a2ui/):
///
/// ```json
/// {
///   "version": "v0.9",
///   "updateComponents": {
///     "surfaceId": "main",
///     "components": [
///       {"id": "root", "component": "node", "name": "form",
///        "children": ["f1"]},
///       {"id": "f1", "component": "field", "name": "Name", "value": "Nico"}
///     ]
///   }
/// }
/// ```
///
/// Components are a flat adjacency list: `component` is the type
/// discriminator string, props sit directly on the component object, and
/// `children` is an ordered list of component ids (containers only).
/// The root is the component with id "root" (v0.9 convention); an optional
/// `rootId` field inside `updateComponents` overrides it (spike extension —
/// NOT part of A2UI v0.9; see NOTES.md fidelity ledger).
///
/// Deserialization goes EXCLUSIVELY through the generated registry
/// (generated/registry.g.dart) — no component type names are hardcoded here.
/// Component ids become Perception keys, which is what lets the perception
/// keyed reconcile turn whole-tree re-emission into an identity-preserving
/// patch.
library;

import 'package:perception/perception.dart';

import 'generated/registry.g.dart';

/// One entry in the flat components list.
class ComponentSpec {
  ComponentSpec({
    required this.id,
    required this.type,
    required this.props,
    required this.childIds,
  });

  factory ComponentSpec.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw StateError(
        'component "id" must be a non-empty string, got: ${json['id']}',
      );
    }
    final type = json['component'];
    if (type is! String) {
      throw StateError(
        'component "$id": "component" (type discriminator) must be a '
        'string, got: ${json['component']}',
      );
    }
    var childIds = const <String>[];
    final childrenRaw = json['children'];
    if (childrenRaw != null) {
      if (childrenRaw is! List || childrenRaw.any((c) => c is! String)) {
        throw StateError(
          'component "$id": "children" must be a list of component id '
          'strings, got: $childrenRaw',
        );
      }
      childIds = childrenRaw.cast<String>();
    }
    return ComponentSpec(
      id: id,
      type: type,
      props: {
        for (final e in json.entries)
          if (e.key != 'id' && e.key != 'component' && e.key != 'children')
            e.key: e.value,
      },
      childIds: childIds,
    );
  }

  /// Stable component id — becomes the Perception key.
  final String id;

  /// Type discriminator (wire field name: "component").
  final String type;

  /// All remaining top-level fields (A2UI v0.9 flat-prop style).
  final Map<String, Object?> props;

  /// Resolved from the wire field "children" (ids, containers only).
  final List<String> childIds;
}

/// Parsed `updateComponents` message.
class SurfaceUpdate {
  SurfaceUpdate({
    required this.surfaceId,
    required this.rootId,
    required this.components,
  });

  /// Parses the full envelope: {"version": "v0.9", "updateComponents": ...}.
  factory SurfaceUpdate.fromJson(Map<String, Object?> json) {
    final body = json['updateComponents'];
    if (body is! Map) {
      throw StateError(
        'message must contain an "updateComponents" object '
        '(A2UI v0.9 shape); got keys: ${json.keys.toList()}',
      );
    }
    final bodyMap = body.cast<String, Object?>();
    final surfaceId = bodyMap['surfaceId'];
    if (surfaceId is! String) {
      throw StateError('"updateComponents.surfaceId" must be a string');
    }
    final componentsRaw = bodyMap['components'];
    if (componentsRaw is! List) {
      throw StateError('"updateComponents.components" must be a list');
    }
    final rootIdRaw = bodyMap['rootId'];
    if (rootIdRaw != null && rootIdRaw is! String) {
      throw StateError('"updateComponents.rootId" must be a string');
    }
    return SurfaceUpdate(
      surfaceId: surfaceId,
      // v0.9 convention: the component with id "root" is the tree root.
      // "rootId" is a spike extension that overrides the convention.
      rootId: (rootIdRaw as String?) ?? 'root',
      components: [
        for (final c in componentsRaw)
          ComponentSpec.fromJson((c as Map).cast<String, Object?>()),
      ],
    );
  }

  final String surfaceId;
  final String rootId;
  final List<ComponentSpec> components;
}

/// Flat list -> Perception tree, via the GENERATED registry only.
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
