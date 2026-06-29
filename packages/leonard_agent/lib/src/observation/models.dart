/// Typed harness-side mirror of the observation bundle returned by
/// `ext.exploration.core.get_stable_observation` (PRD §11.1, §11.3).
///
/// The wire format produced by the binding is:
/// ```json
/// {
///   "semantics": [ {id, role, label?, state?, actions?, rect}, ... ],
///   "routes":    [ "/some/route", ... ],
///   "errors":    [ {seq, message, frames, wallClockOffsetMs}, ... ],
///   "stability": { policy, terminated_by, duration_ms,
///                  framework_busy, extensions_busy: [...] },
///   "extensions":   { "<namespace>": <extension-fragment-data>, ... },
///   "screenshot_png_b64"?: "..."
/// }
/// ```
///
/// On the harness side we re-bundle the top-level `semantics`, `routes`,
/// `errors` keys into a [CoreFragment] so the rest of the harness can talk
/// in `Observation { core, extensions, stability }` terms (PRD §11.1).
///
/// All types are `@immutable`, JSON round-trippable, and value-equal.
library;

import 'dart:collection';

import 'package:meta/meta.dart';

/// Top-level typed observation bundle.
@immutable
class Observation {
  const Observation({
    required this.core,
    required this.extensions,
    required this.stability,
    this.screenshot,
  });

  /// Empty prior used as the "previous observation" on the first turn.
  factory Observation.empty() => Observation(
    core: CoreFragment.empty,
    extensions: const <String, ExtensionFragment>{},
    stability: StabilityMetadata.empty,
  );

  /// Decode a wire-format observation map. Tolerant of missing keys: any
  /// absent top-level field is treated as empty.
  factory Observation.fromJson(Map<String, dynamic> j) {
    final Object? rawSemantics = j['semantics'];
    final Object? rawRoutes = j['routes'];
    final Object? rawErrors = j['errors'];
    final Object? rawStability = j['stability'];
    final Object? rawExtensions = j['extensions'];

    final Map<int, SemanticsNode> nodes = <int, SemanticsNode>{};
    if (rawSemantics is List) {
      for (final Object? entry in rawSemantics) {
        if (entry is! Map) continue;
        final SemanticsNode? node = SemanticsNode.tryFromJson(
          entry.cast<String, dynamic>(),
        );
        if (node != null) nodes[node.id] = node;
      }
    }

    final List<String> routeStack = <String>[];
    if (rawRoutes is List) {
      for (final Object? r in rawRoutes) {
        if (r is String) routeStack.add(r);
      }
    }

    final List<RuntimeError> errors = <RuntimeError>[];
    if (rawErrors is List) {
      for (final Object? e in rawErrors) {
        if (e is! Map) continue;
        errors.add(RuntimeError.fromJson(e.cast<String, dynamic>()));
      }
    }

    final CoreFragment core = CoreFragment(
      routeStack: List<String>.unmodifiable(routeStack),
      nodes: Map<int, SemanticsNode>.unmodifiable(nodes),
      errors: List<RuntimeError>.unmodifiable(errors),
    );

    final Map<String, ExtensionFragment> extensions =
        <String, ExtensionFragment>{};
    if (rawExtensions is Map) {
      rawExtensions.forEach((Object? k, Object? v) {
        if (k is! String) return;
        extensions[k] = ExtensionFragment.fromJson(k, v);
      });
    }

    final StabilityMetadata stability = rawStability is Map
        ? StabilityMetadata.fromJson(rawStability.cast<String, dynamic>())
        : StabilityMetadata.empty;

    final String? screenshot = j['screenshot_png_b64'] as String?;

    return Observation(
      core: core,
      extensions: Map<String, ExtensionFragment>.unmodifiable(extensions),
      stability: stability,
      screenshot: screenshot,
    );
  }

  /// Core fragment (semantics nodes, route stack, runtime errors).
  final CoreFragment core;

  /// Extension fragments keyed by namespace.
  final Map<String, ExtensionFragment> extensions;

  /// Stability metadata block from the binding.
  final StabilityMetadata stability;

  /// Optional base64-encoded PNG screenshot. Present only when the binding
  /// reports `screenshot_png_b64`. Carried through to providers
  /// gated on `capabilities.vision`.
  final String? screenshot;

  Map<String, dynamic> toJson() {
    final List<String> sortedKeys = extensions.keys.toList()..sort();
    return <String, dynamic>{
      'core': core.toJson(),
      'extensions': <String, dynamic>{
        for (final String k in sortedKeys) k: extensions[k]!.toJson(),
      },
      'stability': stability.toJson(),
      if (screenshot != null) 'screenshot_png_b64': screenshot,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is Observation &&
      core == other.core &&
      _mapEq(extensions, other.extensions) &&
      stability == other.stability &&
      screenshot == other.screenshot;

  @override
  int get hashCode => Object.hash(
    core,
    Object.hashAllUnordered(
      extensions.entries.map(
        (MapEntry<String, ExtensionFragment> e) => Object.hash(e.key, e.value),
      ),
    ),
    stability,
    screenshot,
  );
}

/// Core fragment: route stack + semantics nodes (id-keyed) + recent errors.
@immutable
class CoreFragment {
  const CoreFragment({
    required this.routeStack,
    required this.nodes,
    required this.errors,
  });

  static const CoreFragment empty = CoreFragment(
    routeStack: <String>[],
    nodes: <int, SemanticsNode>{},
    errors: <RuntimeError>[],
  );

  /// Best-effort Navigator 1.0 route stack (top route name first/only entry
  /// — see `bestEffortRouteStack` on the binding side).
  final List<String> routeStack;

  /// Captured semantics nodes keyed by stable id.
  final Map<int, SemanticsNode> nodes;

  /// Runtime errors observed since the last cursor.
  final List<RuntimeError> errors;

  Map<String, dynamic> toJson() {
    final List<int> sortedIds = nodes.keys.toList()..sort();
    return <String, dynamic>{
      'routeStack': List<String>.from(routeStack),
      'nodes': <String, dynamic>{
        for (final int id in sortedIds) id.toString(): nodes[id]!.toJson(),
      },
      'errors': errors.map((RuntimeError e) => e.toJson()).toList(),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is CoreFragment &&
      _listEq(routeStack, other.routeStack) &&
      _mapEq(nodes, other.nodes) &&
      _listEq(errors, other.errors);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(routeStack),
    Object.hashAllUnordered(
      nodes.entries.map(
        (MapEntry<int, SemanticsNode> e) => Object.hash(e.key, e.value),
      ),
    ),
    Object.hashAll(errors),
  );
}

/// One semantics node from the captured tree.
///
/// Schema mirrors what the `SemanticsCapture` emits:
/// `{id, role, label?, identifier?, value?, state?, actions?, rect}`. `rect` is
/// a four-int list `[left, top, right, bottom]` in physical pixels.
///
/// `identifier` is the stable, locale-independent key from
/// `Semantics(identifier:)` — preferred for addressing a node across
/// locales/sessions, while `label` (rendered text) is what the model reads to
/// understand what the node is. `value` is a node's current contents — a text
/// field's text, or masked bullets for a secure field. All three are empty
/// when absent.
@immutable
class SemanticsNode {
  const SemanticsNode({
    required this.id,
    required this.role,
    required this.label,
    required this.state,
    required this.actions,
    required this.rect,
    this.identifier = '',
    this.value = '',
    this.scroll,
  });

  /// Decode a record. Returns `null` if `id` or `rect` is malformed; this
  /// keeps the harness defensive against partial wire payloads.
  static SemanticsNode? tryFromJson(Map<String, dynamic> j) {
    final Object? rawId = j['id'];
    if (rawId is! int) return null;
    final Object? rawRect = j['rect'];
    if (rawRect is! List || rawRect.length != 4) return null;
    final List<int> rect = <int>[];
    for (final Object? e in rawRect) {
      if (e is! num) return null;
      rect.add(e.toInt());
    }
    final Object? rawRole = j['role'];
    final Object? rawLabel = j['label'];
    final Object? rawIdentifier = j['identifier'];
    final Object? rawValue = j['value'];
    final Object? rawState = j['state'];
    final Object? rawActions = j['actions'];
    final Object? rawScroll = j['scroll'];
    Map<String, int>? scroll;
    if (rawScroll is Map) {
      final Map<String, int> m = <String, int>{};
      rawScroll.forEach((Object? k, Object? v) {
        if (k is String && v is num) m[k] = v.toInt();
      });
      if (m.isNotEmpty) scroll = Map<String, int>.unmodifiable(m);
    }
    return SemanticsNode(
      id: rawId,
      role: rawRole is String ? rawRole : '',
      label: rawLabel is String ? rawLabel : '',
      identifier: rawIdentifier is String ? rawIdentifier : '',
      value: rawValue is String ? rawValue : '',
      state: rawState is List
          ? List<String>.unmodifiable(rawState.whereType<String>())
          : const <String>[],
      actions: rawActions is List
          ? List<String>.unmodifiable(rawActions.whereType<String>())
          : const <String>[],
      rect: List<int>.unmodifiable(rect),
      scroll: scroll,
    );
  }

  final int id;
  final String role;
  final String label;

  /// Stable, locale-independent key from `Semantics(identifier:)`. Empty when
  /// the app sets none. Preferred for addressing a node; not a substitute for
  /// [label] when reasoning about what the node is.
  final String identifier;

  /// The node's current contents — a text field's text, or masked bullets for
  /// a secure field. Empty when the node has none. Lets the model read what is
  /// already typed instead of relying on the screenshot alone.
  final String value;
  final List<String> state;
  final List<String> actions;

  /// Bounding rect as `[left, top, right, bottom]`.
  final List<int> rect;

  /// Scroll extent for scrollable nodes: `{pos, min?, max?}` in logical
  /// pixels. Null for non-scrollable nodes. Surfaced so the model can scroll
  /// deliberately (it can move `max - pos` further; `pos == max` is the end).
  final Map<String, int>? scroll;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'role': role,
    if (label.isNotEmpty) 'label': label,
    if (identifier.isNotEmpty) 'identifier': identifier,
    if (value.isNotEmpty) 'value': value,
    if (state.isNotEmpty) 'state': List<String>.from(state),
    if (actions.isNotEmpty) 'actions': List<String>.from(actions),
    'rect': List<int>.from(rect),
    if (scroll != null && scroll!.isNotEmpty)
      'scroll': Map<String, int>.from(scroll!),
  };

  @override
  bool operator ==(Object other) =>
      other is SemanticsNode &&
      id == other.id &&
      role == other.role &&
      label == other.label &&
      identifier == other.identifier &&
      value == other.value &&
      _listEq(state, other.state) &&
      _listEq(actions, other.actions) &&
      _listEq(rect, other.rect) &&
      _scrollEq(scroll, other.scroll);

  @override
  int get hashCode => Object.hash(
    id,
    role,
    label,
    identifier,
    value,
    Object.hashAll(state),
    Object.hashAll(actions),
    Object.hashAll(rect),
    scroll == null
        ? null
        : Object.hashAllUnordered(
            scroll!.entries.map(
              (MapEntry<String, int> e) => '${e.key}=${e.value}',
            ),
          ),
  );
}

/// Order-insensitive equality for the optional `scroll` map.
bool _scrollEq(Map<String, int>? a, Map<String, int>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (final MapEntry<String, int> e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}

/// One runtime error captured in the binding's error ring buffer.
@immutable
class RuntimeError {
  const RuntimeError({
    required this.seq,
    required this.message,
    required this.frames,
    required this.wallClockOffsetMs,
  });

  factory RuntimeError.fromJson(Map<String, dynamic> j) {
    final Object? rawSeq = j['seq'];
    final Object? rawMessage = j['message'];
    final Object? rawFrames = j['frames'];
    final Object? rawOffset = j['wallClockOffsetMs'];
    return RuntimeError(
      seq: rawSeq is int ? rawSeq : 0,
      message: rawMessage is String ? rawMessage : '',
      frames: rawFrames is List
          ? List<String>.unmodifiable(rawFrames.whereType<String>())
          : const <String>[],
      wallClockOffsetMs: rawOffset is int ? rawOffset : 0,
    );
  }

  final int seq;
  final String message;
  final List<String> frames;
  final int wallClockOffsetMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'seq': seq,
    'message': message,
    'frames': List<String>.from(frames),
    'wallClockOffsetMs': wallClockOffsetMs,
  };

  @override
  bool operator ==(Object other) =>
      other is RuntimeError &&
      seq == other.seq &&
      message == other.message &&
      _listEq(frames, other.frames) &&
      wallClockOffsetMs == other.wallClockOffsetMs;

  @override
  int get hashCode =>
      Object.hash(seq, message, Object.hashAll(frames), wallClockOffsetMs);
}

/// One extension's contribution to the observation bundle.
///
/// Wire shape today is just `extensions: { ns: <bare-data-map> }`.
/// The harness wraps each entry into [ExtensionFragment] with `namespace =
/// ns`, `data = bare-data-map`, and `deltaFriendly` driven by an opt-in
/// flag the extension can set under either `_delta_friendly` or
/// `delta_friendly` inside its data map. Default: `false` (i.e. the
/// differ falls back to `previous/current` opaque diffs — PRD §11.3).
@immutable
class ExtensionFragment {
  const ExtensionFragment({
    required this.namespace,
    required this.data,
    required this.deltaFriendly,
  });

  /// Decode a single extension fragment. [namespace] is the key from the
  /// outer `extensions` map; [raw] is whatever the binding emitted under it.
  factory ExtensionFragment.fromJson(String namespace, Object? raw) {
    Map<String, dynamic> data;
    bool deltaFriendly = false;
    if (raw is Map) {
      data = Map<String, dynamic>.from(raw);
      // Allow a richer envelope shape in case future work upgrades
      // the wire to carry an explicit envelope.
      final Object? envNs = data['namespace'];
      final Object? envData = data['data'];
      final Object? envDelta = data['delta_friendly'];
      if (envNs is String && envData is Map) {
        // Envelope shape — peel.
        data = Map<String, dynamic>.from(envData);
        if (envDelta is bool) deltaFriendly = envDelta;
      } else {
        // Bare shape — look for the per-fragment opt-in flags.
        final Object? flag = data['_delta_friendly'] ?? data['delta_friendly'];
        if (flag is bool) deltaFriendly = flag;
      }
    } else {
      data = const <String, dynamic>{};
    }
    return ExtensionFragment(
      namespace: namespace,
      data: Map<String, dynamic>.unmodifiable(data),
      deltaFriendly: deltaFriendly,
    );
  }

  final String namespace;
  final Map<String, dynamic> data;
  final bool deltaFriendly;

  Map<String, dynamic> toJson() {
    final List<String> sortedKeys = data.keys.toList()..sort();
    return <String, dynamic>{
      'namespace': namespace,
      'data': <String, dynamic>{for (final String k in sortedKeys) k: data[k]},
      'delta_friendly': deltaFriendly,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ExtensionFragment &&
      namespace == other.namespace &&
      deltaFriendly == other.deltaFriendly &&
      _deepEq(data, other.data);

  @override
  int get hashCode => Object.hash(namespace, deltaFriendly, _deepHash(data));
}

/// Subset of the binding's per-extension "busy at termination" descriptor.
@immutable
class ExtensionBusy {
  const ExtensionBusy({required this.namespace, this.reason, this.estMs});

  factory ExtensionBusy.fromJson(Map<String, dynamic> j) => ExtensionBusy(
    namespace: (j['namespace'] is String) ? j['namespace'] as String : '',
    reason: (j['reason'] is String) ? j['reason'] as String : null,
    estMs: (j['est_ms'] is int) ? j['est_ms'] as int : null,
  );

  final String namespace;
  final String? reason;
  final int? estMs;

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> m = <String, dynamic>{'namespace': namespace};
    if (reason != null) m['reason'] = reason;
    if (estMs != null) m['est_ms'] = estMs;
    return m;
  }

  @override
  bool operator ==(Object other) =>
      other is ExtensionBusy &&
      namespace == other.namespace &&
      reason == other.reason &&
      estMs == other.estMs;

  @override
  int get hashCode => Object.hash(namespace, reason, estMs);
}

/// Wire-typed mirror of the binding's stability block.
@immutable
class StabilityMetadata {
  const StabilityMetadata({
    required this.policy,
    required this.terminatedBy,
    required this.durationMs,
    required this.frameworkBusy,
    required this.extensionsBusy,
  });

  static const StabilityMetadata empty = StabilityMetadata(
    policy: '',
    terminatedBy: '',
    durationMs: 0,
    frameworkBusy: <String, dynamic>{},
    extensionsBusy: <ExtensionBusy>[],
  );

  factory StabilityMetadata.fromJson(Map<String, dynamic> j) {
    final List<ExtensionBusy> busy = <ExtensionBusy>[];
    final Object? raw = j['extensions_busy'];
    if (raw is List) {
      for (final Object? e in raw) {
        if (e is Map)
          busy.add(ExtensionBusy.fromJson(e.cast<String, dynamic>()));
      }
    }
    return StabilityMetadata(
      policy: (j['policy'] is String) ? j['policy'] as String : '',
      terminatedBy: (j['terminated_by'] is String)
          ? j['terminated_by'] as String
          : '',
      durationMs: (j['duration_ms'] is int) ? j['duration_ms'] as int : 0,
      frameworkBusy: (j['framework_busy'] is Map)
          ? Map<String, dynamic>.unmodifiable(
              (j['framework_busy'] as Map).cast<String, dynamic>(),
            )
          : const <String, dynamic>{},
      extensionsBusy: List<ExtensionBusy>.unmodifiable(busy),
    );
  }

  final String policy;
  final String terminatedBy;
  final int durationMs;
  final Map<String, dynamic> frameworkBusy;
  final List<ExtensionBusy> extensionsBusy;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'policy': policy,
    'terminated_by': terminatedBy,
    'duration_ms': durationMs,
    'framework_busy': Map<String, dynamic>.from(frameworkBusy),
    'extensions_busy': extensionsBusy
        .map((ExtensionBusy p) => p.toJson())
        .toList(),
  };

  @override
  bool operator ==(Object other) =>
      other is StabilityMetadata &&
      policy == other.policy &&
      terminatedBy == other.terminatedBy &&
      durationMs == other.durationMs &&
      _deepEq(frameworkBusy, other.frameworkBusy) &&
      _listEq(extensionsBusy, other.extensionsBusy);

  @override
  int get hashCode => Object.hash(
    policy,
    terminatedBy,
    durationMs,
    _deepHash(frameworkBusy),
    Object.hashAll(extensionsBusy),
  );
}

// ---- helpers ----

bool _listEq<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEq<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final K k in a.keys) {
    if (!b.containsKey(k)) return false;
    if (a[k] != b[k]) return false;
  }
  return true;
}

/// Deep value equality for arbitrary JSON values (Maps, Lists, scalars).
bool _deepEq(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final Object? k in a.keys) {
      if (!b.containsKey(k)) return false;
      if (!_deepEq(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (!_deepEq(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

int _deepHash(Object? v) {
  if (v is Map) {
    // Order-independent across keys, order-dependent within values for
    // List values.
    final SplayTreeMap<dynamic, dynamic> sorted =
        SplayTreeMap<dynamic, dynamic>(
          (dynamic a, dynamic b) => a.toString().compareTo(b.toString()),
        )..addAll(v);
    return Object.hashAll(<int>[
      for (final MapEntry<dynamic, dynamic> e in sorted.entries)
        Object.hash(e.key, _deepHash(e.value)),
    ]);
  }
  if (v is List) return Object.hashAll(v.map(_deepHash));
  return v.hashCode;
}
