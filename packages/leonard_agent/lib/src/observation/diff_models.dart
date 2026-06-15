/// Typed result of [ObservationDiffer.diff] (PRD §11.3, §11.4).
///
/// Diff is harness-authored, fed verbatim into the next prompt
/// and into the trajectory. Output is deterministic: maps emit
/// keys in sorted order so identical inputs produce byte-identical JSON.
library;

import 'package:meta/meta.dart';

import 'models.dart';

/// Top-level diff: per-turn delta over [Observation].
@immutable
class ObservationDiff {
  const ObservationDiff({required this.core, required this.extensions});

  /// Empty diff — no route/node/error changes, no extension entries.
  /// Used by validation-retry to append synthetic UserTurns carrying only
  /// a `toolResult` (no real observation change).
  factory ObservationDiff.empty() => const ObservationDiff(
    core: CoreDiff(
      routeChanges: <RouteChange>[],
      nodesAdded: <SemanticsNode>[],
      nodesRemoved: <int>[],
      nodesChanged: <NodeChange>[],
      errorsAdded: <RuntimeError>[],
    ),
    extensions: <String, ExtensionDiff>{},
  );

  /// Diff over the core fragment.
  final CoreDiff core;

  /// Per-namespace extension diff.
  final Map<String, ExtensionDiff> extensions;

  Map<String, dynamic> toJson() {
    final List<String> sortedKeys = extensions.keys.toList()..sort();
    return <String, dynamic>{
      'core': core.toJson(),
      'extensions': <String, dynamic>{
        for (final String k in sortedKeys) k: extensions[k]!.toJson(),
      },
    };
  }
}

/// Diff over the core fragment.
@immutable
class CoreDiff {
  const CoreDiff({
    required this.routeChanges,
    required this.nodesAdded,
    required this.nodesRemoved,
    required this.nodesChanged,
    required this.errorsAdded,
  });

  /// At most one [RouteChange] (or empty when the route stack is unchanged).
  final List<RouteChange> routeChanges;

  /// Nodes appearing in `curr` but absent from `prev`, sorted by id.
  final List<SemanticsNode> nodesAdded;

  /// Stable ids present in `prev` but absent from `curr`, sorted ascending.
  final List<int> nodesRemoved;

  /// Nodes whose content changed between turns, sorted by id.
  final List<NodeChange> nodesChanged;

  /// Runtime errors seen in `curr` that were not in `prev`.
  final List<RuntimeError> errorsAdded;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'routeChanges': routeChanges.map((RouteChange r) => r.toJson()).toList(),
    'nodesAdded': nodesAdded.map((SemanticsNode n) => n.toJson()).toList(),
    'nodesRemoved': List<int>.from(nodesRemoved),
    'nodesChanged': nodesChanged.map((NodeChange c) => c.toJson()).toList(),
    'errorsAdded': errorsAdded.map((RuntimeError e) => e.toJson()).toList(),
  };
}

/// Sealed extension diff; one of [ExtensionDiffStructured], [ExtensionDiffOpaque],
/// [ExtensionDiffAdded], [ExtensionDiffRemoved].
@immutable
sealed class ExtensionDiff {
  const ExtensionDiff();
  Map<String, dynamic> toJson();
}

/// Key-level structured diff. Selected when both `prev` and `curr`
/// declared `deltaFriendly: true`.
class ExtensionDiffStructured extends ExtensionDiff {
  const ExtensionDiffStructured({
    required this.added,
    required this.removed,
    required this.changed,
  });

  final Map<String, dynamic> added;
  final Map<String, dynamic> removed;
  final Map<String, ChangedValue> changed;

  @override
  Map<String, dynamic> toJson() {
    final List<String> addedKeys = added.keys.toList()..sort();
    final List<String> removedKeys = removed.keys.toList()..sort();
    final List<String> changedKeys = changed.keys.toList()..sort();
    return <String, dynamic>{
      'kind': 'structured',
      'added': <String, dynamic>{for (final String k in addedKeys) k: added[k]},
      'removed': <String, dynamic>{
        for (final String k in removedKeys) k: removed[k],
      },
      'changed': <String, dynamic>{
        for (final String k in changedKeys) k: changed[k]!.toJson(),
      },
    };
  }
}

/// Opaque pair (`previous`, `current`). Used when either side is not
/// `deltaFriendly`.
class ExtensionDiffOpaque extends ExtensionDiff {
  const ExtensionDiffOpaque({required this.previous, required this.current});

  final Object? previous;
  final Object? current;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': 'opaque',
    'previous': previous,
    'current': current,
  };
}

/// Extension namespace appears in `curr` but not in `prev`.
class ExtensionDiffAdded extends ExtensionDiff {
  const ExtensionDiffAdded({required this.current});

  final Object? current;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': 'added',
    'current': current,
  };
}

/// Extension namespace appears in `prev` but not in `curr` (e.g. extension
/// auto-disabled).
class ExtensionDiffRemoved extends ExtensionDiff {
  const ExtensionDiffRemoved({required this.previous});

  final Object? previous;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': 'removed',
    'previous': previous,
  };
}

/// One route-stack change: previous full stack -> current full stack.
@immutable
class RouteChange {
  const RouteChange({required this.previous, required this.current});

  final List<String> previous;
  final List<String> current;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'previous': List<String>.from(previous),
    'current': List<String>.from(current),
  };
}

/// One semantics node whose content differs between `prev` and `curr`.
@immutable
class NodeChange {
  const NodeChange({required this.prev, required this.curr});

  final SemanticsNode prev;
  final SemanticsNode curr;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'prev': prev.toJson(),
    'curr': curr.toJson(),
  };
}

/// One key-level change inside a structured extension diff.
@immutable
class ChangedValue {
  const ChangedValue({required this.prev, required this.curr});

  final Object? prev;
  final Object? curr;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'prev': prev,
    'curr': curr,
  };
}
