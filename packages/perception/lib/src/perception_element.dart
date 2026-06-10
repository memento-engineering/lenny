import 'perception.dart';
import 'perception_context.dart';

/// Mounted, live node in the Perception tree — the Element analog.
///
/// Owns lifecycle (mount/update/unmount) and keyed reconciliation.
abstract class PerceptionElement implements PerceptionContext {
  PerceptionElement(Perception perception)
    : _perception = perception,
      perceptionId = (_idCounter++).toString();

  Perception _perception;

  /// The current [Perception] configuration for this element.
  Perception get perception => _perception;

  static int _idCounter = 0;

  // --- PerceptionContext ---

  @override
  final String perceptionId;

  @override
  Object? get key => _perception.key;

  @override
  T? dependOnInheritedPerceptionOfExactType<T extends Object>() => null;

  @override
  void markNeedsHarvest() => _needsHarvest = true;

  // --- Internal state ---

  // ignore: unused_field
  PerceptionElement? _parent;
  bool _mounted = false;
  // ignore: unused_field
  bool _needsHarvest = false;

  /// Whether this element is currently mounted in the tree.
  bool get mounted => _mounted;

  // --- Lifecycle ---

  /// Attaches this element into the tree under [parent] at [slot].
  void mount(PerceptionElement? parent, Object? slot) {
    assert(
      !_mounted,
      'mount() called on already-mounted element (id=$perceptionId).',
    );
    _parent = parent;
    _mounted = true;
  }

  /// Updates the config node when [Perception.canUpdate] is true.
  void update(Perception newPerception) {
    assert(
      _mounted,
      'update() called on unmounted element (id=$perceptionId).',
    );
    assert(
      Perception.canUpdate(_perception, newPerception),
      'update() called with a Perception that fails canUpdate; '
      'use unmount() + mount() for type/key changes.',
    );
    _perception = newPerception;
  }

  /// Detaches this element from the tree.
  void unmount() {
    assert(
      _mounted,
      'unmount() called on already-unmounted element (id=$perceptionId).',
    );
    _mounted = false;
    _parent = null;
  }

  // --- Single-child reconciliation ---

  /// Reconciles [child] against [newPerception] at [slot].
  PerceptionElement? updateChild(
    PerceptionElement? child,
    Perception? newPerception,
    Object? slot,
  ) {
    if (newPerception == null) {
      child?.unmount();
      return null;
    }
    if (child != null) {
      if (Perception.canUpdate(child._perception, newPerception)) {
        child.update(newPerception);
        return child;
      }
      child.unmount();
    }
    final el = newPerception.createElement();
    el.mount(this, slot);
    return el;
  }

  // --- Multi-child keyed reconciliation ---

  /// Reconciles [oldChildren] against [newPerceptions] by key identity.
  List<PerceptionElement> updateChildren(
    List<PerceptionElement> oldChildren,
    List<Perception> newPerceptions,
  ) {
    final Map<Object, PerceptionElement> keyedOld = {};
    final List<PerceptionElement> unkeyedOld = [];
    for (final el in oldChildren) {
      if (el._perception.key != null) {
        keyedOld[el._perception.key!] = el;
      } else {
        unkeyedOld.add(el);
      }
    }

    int unkeyedCursor = 0;
    final result = <PerceptionElement>[];

    for (int i = 0; i < newPerceptions.length; i++) {
      final newP = newPerceptions[i];
      PerceptionElement? match;
      if (newP.key != null) {
        match = keyedOld.remove(newP.key);
      } else if (unkeyedCursor < unkeyedOld.length) {
        match = unkeyedOld[unkeyedCursor++];
      }

      if (match != null && Perception.canUpdate(match._perception, newP)) {
        match.update(newP);
        result.add(match);
      } else {
        match?.unmount();
        final el = newP.createElement();
        el.mount(this, i);
        result.add(el);
      }
    }

    for (final el in keyedOld.values) {
      el.unmount();
    }
    for (int i = unkeyedCursor; i < unkeyedOld.length; i++) {
      unkeyedOld[i].unmount();
    }

    return result;
  }
}
