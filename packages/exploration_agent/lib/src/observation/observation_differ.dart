/// Per-turn structural diff between two [Observation] snapshots.
///
/// PRD §11.3: harness authors the diff. Plugins owning a delta-friendly
/// shape get a structured key-level delta; opaque blobs fall back to a
/// previous-vs-current pair. First-turn behaviour is "all-added" because
/// the prior is `Observation.empty()`.
library;

import 'diff_models.dart';
import 'models.dart';

/// Stateless differ. All routines are pure functions of the two inputs.
class ObservationDiffer {
  const ObservationDiffer._();

  /// Diff `prev` against `curr`. The result is harness-authored and
  /// included verbatim in the next prompt (cx6.13) and the trajectory
  /// (cx6.19).
  static ObservationDiff diff(Observation prev, Observation curr) {
    return ObservationDiff(
      core: _coreDiff(prev.core, curr.core),
      plugins: _pluginsDiff(prev.plugins, curr.plugins),
    );
  }

  static CoreDiff _coreDiff(CoreFragment p, CoreFragment c) {
    final List<SemanticsNode> added = <SemanticsNode>[];
    final List<int> removed = <int>[];
    final List<NodeChange> changed = <NodeChange>[];

    // Added/changed: walk current ids.
    for (final int id in c.nodes.keys) {
      final SemanticsNode? prevNode = p.nodes[id];
      final SemanticsNode currNode = c.nodes[id]!;
      if (prevNode == null) {
        added.add(currNode);
      } else if (prevNode != currNode) {
        changed.add(NodeChange(prev: prevNode, curr: currNode));
      }
    }
    // Removed: walk previous ids.
    for (final int id in p.nodes.keys) {
      if (!c.nodes.containsKey(id)) removed.add(id);
    }

    added.sort((SemanticsNode a, SemanticsNode b) => a.id.compareTo(b.id));
    removed.sort();
    changed.sort(
      (NodeChange a, NodeChange b) => a.curr.id.compareTo(b.curr.id),
    );

    final List<RouteChange> routeChanges = _listEq(p.routeStack, c.routeStack)
        ? const <RouteChange>[]
        : <RouteChange>[
            RouteChange(
              previous: List<String>.from(p.routeStack),
              current: List<String>.from(c.routeStack),
            ),
          ];

    final List<RuntimeError> errorsAdded = <RuntimeError>[];
    final Set<int> prevSeqs =
        p.errors.map((RuntimeError e) => e.seq).toSet();
    for (final RuntimeError e in c.errors) {
      // The binding's error ring buffer assigns monotonically increasing
      // seq numbers. Anything in `curr` whose seq we did not see in
      // `prev` is "new this turn".
      if (!prevSeqs.contains(e.seq)) errorsAdded.add(e);
    }

    return CoreDiff(
      routeChanges: routeChanges,
      nodesAdded: added,
      nodesRemoved: removed,
      nodesChanged: changed,
      errorsAdded: errorsAdded,
    );
  }

  static Map<String, PluginDiff> _pluginsDiff(
    Map<String, PluginFragment> p,
    Map<String, PluginFragment> c,
  ) {
    final Map<String, PluginDiff> out = <String, PluginDiff>{};
    for (final String ns in c.keys) {
      final PluginFragment curr = c[ns]!;
      final PluginFragment? prev = p[ns];
      if (prev == null) {
        out[ns] = PluginDiffAdded(current: curr.data);
        continue;
      }
      if (curr.deltaFriendly && prev.deltaFriendly) {
        out[ns] = _structuredDiff(prev.data, curr.data);
      } else {
        out[ns] = PluginDiffOpaque(previous: prev.data, current: curr.data);
      }
    }
    for (final String ns in p.keys) {
      if (!c.containsKey(ns)) {
        out[ns] = PluginDiffRemoved(previous: p[ns]!.data);
      }
    }
    return out;
  }

  static PluginDiffStructured _structuredDiff(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final Map<String, dynamic> added = <String, dynamic>{};
    final Map<String, dynamic> removed = <String, dynamic>{};
    final Map<String, ChangedValue> changed = <String, ChangedValue>{};
    for (final String k in b.keys) {
      if (!a.containsKey(k)) {
        added[k] = b[k];
      } else if (!_jsonEq(a[k], b[k])) {
        changed[k] = ChangedValue(prev: a[k], curr: b[k]);
      }
    }
    for (final String k in a.keys) {
      if (!b.containsKey(k)) removed[k] = a[k];
    }
    return PluginDiffStructured(
      added: added,
      removed: removed,
      changed: changed,
    );
  }

  static bool _listEq<T>(List<T> a, List<T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Deep value equality for arbitrary JSON values. We need this rather
  /// than `==` because nested Map/List literals don't compare structurally
  /// in Dart.
  static bool _jsonEq(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final Object? k in a.keys) {
        if (!b.containsKey(k)) return false;
        if (!_jsonEq(a[k], b[k])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (int i = 0; i < a.length; i++) {
        if (!_jsonEq(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }
}
