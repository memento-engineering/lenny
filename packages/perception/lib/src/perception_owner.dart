import 'dart:collection';

import 'perception.dart';
import 'perception_element.dart';

typedef VoidCallback = void Function();

/// Owns the root element, holds the dirty set, and drives synchronous
/// depth-ordered flushes — the BuildOwner.buildScope analog.
class PerceptionOwner {
  final SplayTreeSet<PerceptionElement> _dirty = SplayTreeSet((a, b) {
    final d = a.depth.compareTo(b.depth);
    return d != 0 ? d : a.perceptionId.compareTo(b.perceptionId);
  });

  VoidCallback? onNeedsHarvest;
  PerceptionElement? _root;
  int _nextId = 0;

  // null when idle; non-null during a flush pass (debug-only — always null in release)
  Set<PerceptionElement>? _builtThisPass;

  String issueId() => (_nextId++).toString();

  PerceptionElement mountRoot(Perception perception) {
    assert(
      _root == null,
      'mountRoot called with an existing root; call unmountRoot() first',
    );
    final el = perception.createElement();
    el.owner = this;
    el.mount(null, null);
    _root = el;
    return el;
  }

  void scheduleHarvestFor(PerceptionElement element) {
    assert(
      _builtThisPass == null || !_builtThisPass!.contains(element),
      'element ${element.perceptionId} re-dirtied after it was already built '
      'in this flushHarvest pass; performRebuild must not re-dirty an '
      'already-built element',
    );
    final wasEmpty = _dirty.isEmpty;
    _dirty.add(element);
    if (wasEmpty) onNeedsHarvest?.call();
  }

  void flushHarvest() {
    assert(() {
      _builtThisPass = {};
      return true;
    }());
    try {
      while (_dirty.isNotEmpty) {
        final el = _dirty.first;
        _dirty.remove(el);
        el.rebuild();
        assert(() {
          _builtThisPass!.add(el);
          return true;
        }());
      }
    } finally {
      assert(() {
        _builtThisPass = null;
        return true;
      }());
    }
  }

  void unmountRoot() {
    if (_root?.mounted == true) _root!.unmount();
    _root = null;
  }

  void dispose() {
    unmountRoot();
    _dirty.clear();
  }
}
