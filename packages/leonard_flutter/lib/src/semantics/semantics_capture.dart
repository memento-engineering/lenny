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
  Future<List<Map<String, Object>>> captureAsync() async {
    _semanticsHandle ??= SemanticsBinding.instance.ensureSemantics();
    SemanticsNode? root = _findRootSemanticsNode();
    if (root == null) {
      try {
        await SchedulerBinding.instance.endOfFrame.timeout(
          const Duration(milliseconds: 250),
        );
      } on TimeoutException {
        return const <Map<String, Object>>[];
      }
      root = _findRootSemanticsNode();
    }
    if (root == null) return const <Map<String, Object>>[];
    final ui.FlutterView v =
        WidgetsBinding.instance.platformDispatcher.views.first;
    final Rect viewport = Offset.zero & v.physicalSize;
    final List<_Rec> recs = <_Rec>[];
    _walk(root, recs, viewport, v.devicePixelRatio);
    return recs.map((_Rec r) => r.toJson()).toList(growable: false);
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
    final ui.FlutterView v =
        WidgetsBinding.instance.platformDispatcher.views.first;
    final Rect viewport = Offset.zero & v.physicalSize;
    final List<_Rec> recs = <_Rec>[];
    _walk(root, recs, viewport, v.devicePixelRatio);
    return recs.map((_Rec r) => r.toJson()).toList(growable: false);
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

extension _SemanticsCaptureWalk on SemanticsCapture {
  void _walk(
    SemanticsNode n,
    List<_Rec> out,
    Rect viewport,
    double dpr, [
    Matrix4? parentTransform,
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
    out.add(
      _Rec(
        _stableIdFor(n),
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
      _walk(c, out, viewport, dpr, global);
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
