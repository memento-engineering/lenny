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

  /// Decodes the bundled shape emitted by [toJson].
  factory ObservationDiff.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> coreJson = Map<String, dynamic>.from(
      json['core'] as Map? ?? const <String, dynamic>{},
    );
    final Map<String, ExtensionDiff> extensions = <String, ExtensionDiff>{};
    final Object? rawExtensions = json['extensions'];
    if (rawExtensions is Map) {
      rawExtensions.forEach((Object? key, Object? value) {
        if (key is! String || value is! Map) return;
        extensions[key] = _extensionDiffFromJson(
          Map<String, dynamic>.from(value),
        );
      });
    }
    return ObservationDiff(
      core: _coreDiffFromJson(coreJson),
      extensions: Map<String, ExtensionDiff>.unmodifiable(extensions),
    );
  }

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

CoreDiff _coreDiffFromJson(Map<String, dynamic> json) => CoreDiff(
  routeChanges: <RouteChange>[
    for (final Object? value in json['routeChanges'] as List? ?? const [])
      if (value is Map) _routeChangeFromJson(Map<String, dynamic>.from(value)),
  ],
  nodesAdded: <SemanticsNode>[
    for (final Object? value in json['nodesAdded'] as List? ?? const [])
      if (value is Map) _semanticsNodeFromJson(value),
  ],
  nodesRemoved: <int>[
    for (final Object? value in json['nodesRemoved'] as List? ?? const [])
      if (value is num) value.toInt(),
  ],
  nodesChanged: <NodeChange>[
    for (final Object? value in json['nodesChanged'] as List? ?? const [])
      if (value is Map) _nodeChangeFromJson(value),
  ],
  errorsAdded: <RuntimeError>[
    for (final Object? value in json['errorsAdded'] as List? ?? const [])
      if (value is Map) RuntimeError.fromJson(Map<String, dynamic>.from(value)),
  ],
);

RouteChange _routeChangeFromJson(Map<String, dynamic> json) => RouteChange(
  previous: <String>[
    for (final Object? value in json['previous'] as List? ?? const [])
      if (value is String) value,
  ],
  current: <String>[
    for (final Object? value in json['current'] as List? ?? const [])
      if (value is String) value,
  ],
);

NodeChange _nodeChangeFromJson(Map<dynamic, dynamic> json) => NodeChange(
  prev: _semanticsNodeFromJson(json['prev']),
  curr: _semanticsNodeFromJson(json['curr']),
);

SemanticsNode _semanticsNodeFromJson(Object? value) {
  if (value is Map) {
    final SemanticsNode? node = SemanticsNode.tryFromJson(
      Map<String, dynamic>.from(value),
    );
    if (node != null) return node;
  }
  throw const FormatException('invalid semantics node in observation diff');
}

ChangedValue _changedValueFromJson(Map<dynamic, dynamic> json) =>
    ChangedValue(prev: json['prev'], curr: json['curr']);

ExtensionDiff _extensionDiffFromJson(Map<String, dynamic> json) {
  switch (json['kind']) {
    case 'structured':
      final Map<String, ChangedValue> changed = <String, ChangedValue>{};
      final Object? rawChanged = json['changed'];
      if (rawChanged is Map) {
        rawChanged.forEach((Object? key, Object? value) {
          if (key is String && value is Map) {
            changed[key] = _changedValueFromJson(value);
          }
        });
      }
      return ExtensionDiffStructured(
        added: Map<String, dynamic>.from(
          json['added'] as Map? ?? const <String, dynamic>{},
        ),
        removed: Map<String, dynamic>.from(
          json['removed'] as Map? ?? const <String, dynamic>{},
        ),
        changed: changed,
      );
    case 'opaque':
      return ExtensionDiffOpaque(
        previous: json['previous'],
        current: json['current'],
      );
    case 'added':
      return ExtensionDiffAdded(current: json['current']);
    case 'removed':
      return ExtensionDiffRemoved(previous: json['previous']);
    default:
      throw FormatException('unknown extension diff kind: ${json['kind']}');
  }
}
