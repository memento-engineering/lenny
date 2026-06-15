/// A mounted A2UI surface: deserialized wire message -> live perception tree.
///
/// Owns the [PerceptionOwner], exposes the mounted root, accepts whole-tree
/// re-emissions through the SAME wire path as the initial mount (keyed
/// reconcile turns them into in-place patches — spike3 check d), and provides
/// the hit-test primitives the action router needs: [findById] against the
/// LIVE tree, and the ever-seen id set that distinguishes "never existed"
/// from "the projection moved under the actor".
library;

import 'dart:async';

import 'package:perception/perception.dart';
import 'package:spike3_schema_roundtrip/src/field.dart';
import 'package:spike3_schema_roundtrip/src/wire.dart' show SurfaceUpdate;

import 'src/components.dart';
import 'src/wire5.dart';

class Surface {
  /// Mounts the surface described by an A2UI v0.9 `updateComponents`
  /// envelope (decoded JSON).
  Surface.mount(Map<String, Object?> message) {
    final update = SurfaceUpdate.fromJson(message);
    surfaceId = update.surfaceId;
    everSeenIds.addAll([for (final c in update.components) c.id]);
    root = owner.mountRoot(buildPerceptionTree(update));
    // Perception contract: onNeedsHarvest fires when the dirty set goes
    // empty -> non-empty; schedule the flush there (microtask). Tests may
    // also call flush() synchronously; the microtask then no-ops.
    owner.onNeedsHarvest = () {
      _pendingHarvest = true;
      scheduleMicrotask(() {
        if (_pendingHarvest) flush();
      });
    };
  }

  final PerceptionOwner owner = PerceptionOwner();
  late final String surfaceId;
  late final PerceptionElement root;

  /// Every component id seen in ANY applied emission of this surface
  /// (v1, v2, ...). Lets the router distinguish Rejection(unknownComponent)
  /// — never existed — from Rejection(staleUnmounted) — previously valid,
  /// but the projection moved under the actor.
  final Set<String> everSeenIds = {};

  bool _pendingHarvest = false;

  /// True between markNeedsHarvest and the next flush.
  bool get hasPendingHarvest => _pendingHarvest;

  /// Drains the owner's depth-ordered dirty set synchronously.
  void flush() {
    _pendingHarvest = false;
    owner.flushHarvest();
  }

  /// Applies a whole-tree re-emission through the same wire path as
  /// [Surface.mount]; the keyed reconcile patches the live tree in place.
  void applyUpdate(Map<String, Object?> message) {
    final update = SurfaceUpdate.fromJson(message);
    if (update.surfaceId != surfaceId) {
      throw StateError(
        'surface "$surfaceId" received an update for "${update.surfaceId}"',
      );
    }
    everSeenIds.addAll([for (final c in update.components) c.id]);
    root.update(buildPerceptionTree(update));
  }

  /// Hit-test primitive: the LIVE mounted element whose Perception key
  /// equals [id], or null. Walks the tree from the root on every call — the
  /// router never holds stale element references.
  PerceptionElement? findById(String id) {
    PerceptionElement? hit;
    void visit(PerceptionElement el) {
      if (hit != null) return;
      if (el.mounted && el.perception.key == id) {
        hit = el;
        return;
      }
      for (final child in childrenOf(el)) {
        visit(child);
      }
    }

    visit(root);
    return hit;
  }

  /// Children of a live element. PerceptionElement has no generic
  /// visitChildren API yet, so dispatch on the known element shapes
  /// (NodeElement.children / ComponentElement.child are test-only getters).
  /// Production feedback for perception: a visitChildren API.
  static List<PerceptionElement> childrenOf(PerceptionElement el) {
    if (el is NodeElement) return el.children;
    if (el is ComponentElement) {
      final child = el.child;
      return child == null ? const [] : [child];
    }
    return const []; // leaf (e.g. FieldElement)
  }

  /// Canonical structural dump of the LIVE tree — config props AND live
  /// state. Tests capture this before/after a rejected action to prove the
  /// rejection left the tree byte-for-byte untouched.
  String dumpLiveTree() => _dump(root);

  static String _dump(PerceptionElement el) {
    final p = el.perception;
    final desc = switch (p) {
      Node n => 'panel(key=${p.key}, name=${n.name})',
      Field f => 'label(key=${p.key}, name=${f.name}, value=${f.value})',
      CounterButton b =>
        'button(key=${p.key}, label=${b.label}, '
            'count=${((el as StatefulElement).state as CounterButtonState).count})',
      _ => '${p.runtimeType}(key=${p.key})',
    };
    final children = childrenOf(el).map(_dump).join(', ');
    return children.isEmpty ? desc : '$desc[$children]';
  }
}
