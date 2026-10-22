import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Walks Flutter's semantics tree and emits compact JSON-friendly records
/// describing visible, interactive nodes.
///
/// Each capture returns a list of records with the schema
/// `id, role, label?, identifier?, value?, hint?, state?, actions?, rect` where
/// `rect` is a four-element integer list `[left, top, right, bottom]`.
///
/// Tooltips: Flutter puts an icon-only control's hover text in
/// [SemanticsData.tooltip], not in [SemanticsData.label] — an
/// `IconButton(icon: …, tooltip: 'Settings')` has an empty label. Leonard
/// promotes it: when a node's `label` is empty and its tooltip is not, the
/// tooltip IS the emitted `label` (that is the text a sighted user reads on
/// hover, and the text a scenario names). When a node has both, the rendered
/// `label` is kept and the tooltip rides alongside it as `hint`. `hint` is
/// therefore never a second copy of `label`, and it carries Flutter's
/// `tooltip` — Flutter's unrelated `SemanticsData.hint` is not surfaced.
///
/// `identifier` is the stable, locale-independent key set by
/// `Semantics(identifier:)` (Flutter's [SemanticsData.identifier]). It is the
/// preferred handle for *addressing* a node across locales/sessions; `label`
/// (rendered text) remains the field to reason about *what a node is*. Emitted
/// only when the app sets one, so targets that don't use identifiers are
/// unaffected.
///
/// Stable ids: the same framework [SemanticsNode] (identified by
/// [SemanticsNode.id]) maps to the same emitted `id` across repeated
/// captures within one binding lifetime. Ids are not guaranteed stable
/// across sessions (PRD section 11.1, 12.3).
///
/// Filtering: off-screen nodes (rect outside the device viewport) and nodes
/// flagged `isHidden` are omitted. Leonard otherwise follows the semantics tree
/// produced by Flutter, including exclusions and blocking applied by widgets
/// such as `ExcludeSemantics` and `BlockSemantics`.
///
/// Route layers: [captureSnapshotAsync] also returns the routes on screen as
/// accessibility services see them; see [SemanticsSnapshot.routeLayers].
class SemanticsCapture {
  /// Creates a new capture instance. The stable-id map is per instance.
  SemanticsCapture();

  final Map<int, int> _stableIds = <int, int>{};
  int _nextId = 1;
  SemanticsHandle? _semanticsHandle;

  /// Test seam: when set, the next [_findRootSemanticsNode] returns null
  /// exactly once and then clears itself.
  ///
  /// This deterministically reproduces the on-device cold-start race — where
  /// `ensureSemantics()` has scheduled the semantics flush but it has not yet
  /// completed on the first read, so the root is momentarily null. The
  /// `flutter_test` harness cannot reproduce that race naturally (its semantics
  /// root is always synchronously available after layout), so a seam is the
  /// only way to exercise the recovery path in a CI widget test. [captureAsync]
  /// recovers by awaiting `endOfFrame` and re-reading; the deprecated [capture]
  /// does not. See `semantics_capture_racing_test.dart`.
  @visibleForTesting
  bool debugRaceNextRootLookup = false;

  int _stableIdFor(SemanticsNode n) =>
      _stableIds.putIfAbsent(n.id, () => _nextId++);

  /// Async-safe form of [capture]. Awaits [SchedulerBinding.instance.endOfFrame]
  /// (with a 250 ms timeout) when [_findRootSemanticsNode] returns null on the
  /// first call, so the semantics flush triggered by [ensureSemantics] can
  /// complete before the tree is walked. On timeout (occluded / non-pumping
  /// window) returns [].
  Future<List<Map<String, Object>>> captureAsync() async =>
      (await captureSnapshotAsync()).nodes;

  /// [captureAsync], plus the route layers read in the same walk, so the two
  /// always describe one capture. Both are empty on the paths where
  /// [captureAsync] returns [].
  Future<SemanticsSnapshot> captureSnapshotAsync() async {
    _semanticsHandle ??= SemanticsBinding.instance.ensureSemantics();
    SemanticsNode? root = _findRootSemanticsNode();
    if (root == null) {
      try {
        await SchedulerBinding.instance.endOfFrame.timeout(
          const Duration(milliseconds: 250),
        );
      } on TimeoutException {
        return SemanticsSnapshot.empty;
      }
      root = _findRootSemanticsNode();
    }
    if (root == null) return SemanticsSnapshot.empty;
    return _snapshot(root);
  }

  /// Retained for backward compat; races the initial semantics flush.
  @Deprecated(
    'Use captureAsync() — the synchronous form races the initial semantics '
    'flush and returns [] on first call on a real device. '
    'Will be removed when all call sites are migrated.',
  )
  List<Map<String, Object>> capture() {
    _semanticsHandle ??= SemanticsBinding.instance.ensureSemantics();
    final SemanticsNode? root = _findRootSemanticsNode();
    if (root == null) {
      return const <Map<String, Object>>[];
    }
    return _snapshot(root).nodes;
  }

  SemanticsSnapshot _snapshot(SemanticsNode root) {
    final ui.FlutterView v =
        WidgetsBinding.instance.platformDispatcher.views.first;
    final Rect viewport = Offset.zero & v.physicalSize;
    final List<_Rec> recs = <_Rec>[];
    final List<_Layer> layers = <_Layer>[];
    _walk(root, recs, viewport, v.devicePixelRatio, layers);
    return SemanticsSnapshot._(
      recs.map((_Rec r) => r.toJson()).toList(growable: false),
      _foldRouteLayers(
        layers,
      ).map((_Layer l) => l.toJson()).toList(growable: false),
    );
  }

  /// Walks the [PipelineOwner] tree rooted at
  /// [RendererBinding.rootPipelineOwner] and returns the first non-null
  /// `rootSemanticsNode` encountered. The framework attaches a child
  /// pipeline owner per `RenderView`; in single-view apps there is one.
  SemanticsNode? _findRootSemanticsNode() {
    if (debugRaceNextRootLookup) {
      debugRaceNextRootLookup = false;
      return null;
    }
    SemanticsNode? found;
    void visit(PipelineOwner owner) {
      if (found != null) return;
      final SemanticsNode? r = owner.semanticsOwner?.rootSemanticsNode;
      if (r != null) {
        found = r;
        return;
      }
      owner.visitChildren(visit);
    }

    visit(RendererBinding.instance.rootPipelineOwner);
    return found;
  }

  /// Releases the [SemanticsHandle] acquired by [capture], if any.
  ///
  /// Safe to call multiple times. After [dispose] the next [capture] call
  /// will acquire a fresh handle.
  void dispose() {
    _semanticsHandle?.dispose();
    _semanticsHandle = null;
  }

  /// Returns the live [SemanticsNode] whose stable id was previously
  /// emitted by [capture] as [stableId], or `null` if no such node was
  /// captured this session OR the node was disposed since capture.
  ///
  /// Re-walks the live semantics tree on every call (no caching beyond
  /// the existing stable-id map). Cheap relative to capture itself.
  SemanticsNode? lookup(int stableId) {
    int? fwkId;
    for (final MapEntry<int, int> e in _stableIds.entries) {
      if (e.value == stableId) {
        fwkId = e.key;
        break;
      }
    }
    if (fwkId == null) return null;
    final SemanticsNode? root = _findRootSemanticsNode();
    if (root == null) return null;
    return _findById(root, fwkId);
  }

  SemanticsNode? _findById(SemanticsNode start, int fwkId) {
    if (start.id == fwkId) return start;
    SemanticsNode? out;
    start.visitChildren((SemanticsNode c) {
      if (out != null) return false;
      final SemanticsNode? hit = _findById(c, fwkId);
      if (hit != null) {
        out = hit;
        return false;
      }
      return true;
    });
    return out;
  }
}

/// One semantics capture: the emitted node records and the route layers read
/// in the same walk.
class SemanticsSnapshot {
  const SemanticsSnapshot._(this.nodes, this.routeLayers);

  /// The snapshot of a capture that found no semantics tree.
  static const SemanticsSnapshot empty = SemanticsSnapshot._(
    <Map<String, Object>>[],
    <Map<String, Object?>>[],
  );

  /// The node records, as [SemanticsCapture.captureAsync] returns them.
  final List<Map<String, Object>> nodes;

  /// The route layers on screen, top-most last: the routes the user can
  /// reach, as accessibility services see them.
  ///
  /// A layer is an emitted node flagged [SemanticsFlag.scopesRoute], the flag
  /// the framework sets on page routes, dialogs, popup menus, bottom sheets,
  /// drawers, dropdowns and search, and that screen readers use to announce a
  /// screen change. Each entry is `{node, name}`: `node` is the emitted `id`
  /// of the scoping node, and `name` is the label of the first node flagged
  /// [SemanticsFlag.namesRoute] with a non-empty label inside that scope, in
  /// depth-first paint order, or null: the text a screen reader announces.
  ///
  /// One layer per route. A scope with no name and no labelled or actionable
  /// node of its own whose only content is one nested scope is folded with
  /// it into one layer, which keeps the outer `node` and takes the inner
  /// name: `showDialog` scopes its route and the `AlertDialog` inside scopes
  /// itself again, and that is one layer named "Alert". The same folding
  /// applies to an unnamed, otherwise empty page around a nested navigator.
  /// A page with its own title or content around a nested navigator stays
  /// its own layer, with the nested route as a second layer above it.
  ///
  /// This is what the user can reach, not the route stack. A modal barrier
  /// hides the routes beneath it from semantics, so under a dialog or a modal
  /// sheet only that dialog or sheet is a layer. A route in a hidden tab is
  /// absent. A page with no app bar title, or a Material page on iOS or macOS
  /// (where an app bar title does not name the route), has a null name, and
  /// so does a page whose non-pinned `SliverAppBar` title has scrolled out
  /// of view, which shows as a layer change. Location, path, arguments and
  /// history belong to a navigation extension.
  final List<Map<String, Object?>> routeLayers;
}

/// Internal representation of an emitted semantics record.
class _Rec {
  _Rec(
    this.id,
    this.role,
    this.label,
    this.identifier,
    this.value,
    this.hint,
    this.state,
    this.actions,
    this.rect, [
    this.scroll,
  ]);

  final int id;
  final String role;
  final String label;

  /// Stable, locale-independent key from `Semantics(identifier:)`. Empty when
  /// the app sets none. Preferred for addressing; not a substitute for [label].
  final String identifier;
  final String value;

  /// Flutter's [SemanticsData.tooltip], carried only when the node ALSO has a
  /// rendered [label] — the hover text a sighted user gets in addition to the
  /// label. Empty when the node has no tooltip, and empty when the tooltip was
  /// promoted into [label] (a label-less control such as an icon-only button),
  /// so `hint` never duplicates `label`.
  final String hint;
  final List<String> state;
  final List<String> actions;
  final Rect rect;

  /// Scroll extent for scrollable nodes: `{pos, min?, max?}` in logical
  /// pixels (`min` omitted when 0, `max` omitted when unbounded/infinite).
  /// Null for non-scrollable nodes. Lets the agent see how far a list can
  /// scroll and whether it is already at the end, instead of guessing.
  final Map<String, Object>? scroll;

  Map<String, Object> toJson() {
    final Map<String, Object> m = <String, Object>{
      'id': id,
      'role': role,
      'rect': <int>[
        rect.left.round(),
        rect.top.round(),
        rect.right.round(),
        rect.bottom.round(),
      ],
    };
    if (label.isNotEmpty) m['label'] = label;
    if (identifier.isNotEmpty) m['identifier'] = identifier;
    if (value.isNotEmpty) m['value'] = value;
    if (hint.isNotEmpty) m['hint'] = hint;
    if (state.isNotEmpty) m['state'] = state;
    if (actions.isNotEmpty) m['actions'] = actions;
    if (scroll != null) m['scroll'] = scroll!;
    return m;
  }
}

/// A route layer being collected by the walk.
class _Layer {
  _Layer(this.node, this.parent);

  final int node;
  final _Layer? parent;
  String? name;

  /// Whether a labelled or actionable node sits in this scope outside any
  /// nested scope.
  bool hasOwnContent = false;

  /// Scopes nested directly in this one.
  final List<_Layer> children = <_Layer>[];

  Map<String, Object?> toJson() => <String, Object?>{
    'node': node,
    'name': name,
  };
}

/// Folds every layer that has no name and no content of its own and holds
/// exactly one nested layer into that layer: the same route scoped twice, as
/// `showDialog`'s route around an `AlertDialog`. The outer node stays and
/// takes the inner one's name. Returns the layers that remain, in order.
List<_Layer> _foldRouteLayers(List<_Layer> preorder) {
  final Set<_Layer> folded = <_Layer>{};
  // Reverse preorder visits nested layers first, so a chain folds fully.
  for (final _Layer l in preorder.reversed) {
    if (l.name != null || l.hasOwnContent || l.children.length != 1) continue;
    final _Layer inner = l.children.single;
    l.name = inner.name;
    l.hasOwnContent = inner.hasOwnContent;
    l.children
      ..clear()
      ..addAll(inner.children);
    folded.add(inner);
  }
  return <_Layer>[
    for (final _Layer l in preorder)
      if (!folded.contains(l)) l,
  ];
}

extension _SemanticsCaptureWalk on SemanticsCapture {
  void _walk(
    SemanticsNode n,
    List<_Rec> out,
    Rect viewport,
    double dpr,
    List<_Layer> layers, [
    Matrix4? parentTransform,
    _Layer? scope,
  ]) {
    final SemanticsData d = n.getSemanticsData();
    if (d.flagsCollection.isHidden) return;
    // SemanticsNode.transform maps a node's local rect into its PARENT's
    // space, not the device's. Applying only the node's own transform
    // collapses every nested row to its parent-local origin — e.g. all
    // list rows resolve to [0,0,w,56]. Accumulate ancestor transforms to get
    // true device-space rects,
    // matching globalRectOf (dispatch.dart).
    final Matrix4 global = (parentTransform ?? Matrix4.identity()).multiplied(
      n.transform ?? Matrix4.identity(),
    );
    final Rect r = MatrixUtils.transformRect(global, n.rect);
    if (!r.overlaps(viewport)) return;
    // Flutter puts an icon-only control's hover text in `tooltip`, not
    // `label`. Promote it when there is no label to read; keep both apart
    // when there is one.
    final String tooltip = d.tooltip;
    final String label = d.label.isEmpty ? tooltip : d.label;
    final String hint = d.label.isEmpty ? '' : tooltip;
    final int id = _stableIdFor(n);
    _Layer? inner = scope;
    if (d.flagsCollection.scopesRoute) {
      inner = _Layer(id, scope);
      scope?.children.add(inner);
      layers.add(inner);
    }
    // The flags may sit on the same node, so a scope can name itself.
    if (inner != null &&
        inner.name == null &&
        d.flagsCollection.namesRoute &&
        d.label.isNotEmpty) {
      inner.name = d.label;
    }
    if (inner != null &&
        !d.flagsCollection.scopesRoute &&
        (label.isNotEmpty || d.value.isNotEmpty || d.actions != 0)) {
      inner.hasOwnContent = true;
    }
    out.add(
      _Rec(
        id,
        _role(d),
        label,
        d.identifier,
        d.value,
        hint,
        _state(d),
        _actions(d),
        r,
        _scroll(d, dpr),
      ),
    );
    n.visitChildren((SemanticsNode c) {
      _walk(c, out, viewport, dpr, layers, global, inner);
      return true;
    });
  }

  String _role(SemanticsData d) {
    final ui.SemanticsFlags f = d.flagsCollection;
    if (f.isButton) return 'button';
    if (f.isTextField) return 'textfield';
    if (f.isLink) return 'link';
    if (f.isHeader) return 'header';
    if (f.isImage) return 'image';
    if (f.isChecked != ui.CheckedState.none) return 'checkbox';
    if (f.isToggled != ui.Tristate.none) return 'switch';
    if (f.isSlider) return 'slider';
    return 'text';
  }

  List<String> _state(SemanticsData d) {
    final ui.SemanticsFlags f = d.flagsCollection;
    final List<String> out = <String>[];
    if (f.isChecked == ui.CheckedState.isTrue) out.add('checked');
    if (f.isToggled == ui.Tristate.isTrue) out.add('on');
    if (f.isSelected == ui.Tristate.isTrue) out.add('selected');
    if (f.isFocused == ui.Tristate.isTrue) out.add('focused');
    if (f.isEnabled == ui.Tristate.isFalse) out.add('disabled');
    if (f.isObscured) out.add('obscured');
    return out;
  }

  List<String> _actions(SemanticsData d) {
    const Map<SemanticsAction, String> t = <SemanticsAction, String>{
      SemanticsAction.tap: 'tap',
      SemanticsAction.longPress: 'long_press',
      SemanticsAction.scrollLeft: 'scroll_left',
      SemanticsAction.scrollRight: 'scroll_right',
      SemanticsAction.scrollUp: 'scroll_up',
      SemanticsAction.scrollDown: 'scroll_down',
      SemanticsAction.increase: 'increase',
      SemanticsAction.decrease: 'decrease',
      SemanticsAction.setText: 'set_text',
    };
    final List<String> out = <String>[];
    t.forEach((SemanticsAction k, String v) {
      if ((d.actions & k.index) != 0) out.add(v);
    });
    return out;
  }

  /// Scroll extent for a scrollable node, or null when the node does not
  /// scroll. Flutter populates `scrollPosition`/`scrollExtentMin/Max` only
  /// on scrollable nodes, so a null `scrollPosition` is the gate.
  ///
  /// Shape: `{pos, min?, max?}` in **physical** pixels (scaled by [dpr] to
  /// match the node `rect`, which is physical) — `min` omitted when 0 (the
  /// common case), `max` omitted when infinite (lazy/unbounded lists, where
  /// the end isn't known ahead of time). With this the agent can tell it can
  /// scroll `max - pos` further, or that `pos == max` means it's at the
  /// bottom — instead of blindly guessing `delta_pixels`.
  Map<String, Object>? _scroll(SemanticsData d, double dpr) {
    final double? pos = d.scrollPosition;
    if (pos == null || !pos.isFinite) return null;
    final Map<String, Object> s = <String, Object>{'pos': (pos * dpr).round()};
    final double? min = d.scrollExtentMin;
    if (min != null && min.isFinite && min != 0) s['min'] = (min * dpr).round();
    final double? max = d.scrollExtentMax;
    if (max != null && max.isFinite) s['max'] = (max * dpr).round();
    return s;
  }
}
