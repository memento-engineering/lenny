/// The cached snapshot of a native app's accessibility tree — the raw material
/// the perception projection turns into the `native` observation fragment.
///
/// [NativeNode] carries the **canonical cross-host record schema**: the exact
/// same shape the Flutter semantics fragment emits, so an agent driving Flutter
/// vs native sees a byte-identical per-node record.
library;

import 'package:meta/meta.dart';

/// One perceived node of the native a11y tree, carrying the canonical
/// cross-host record schema.
///
/// `rect` is a 4-int `[left, top, right, bottom]` (NOT `{x,y,w,h}`, NOT
/// doubles). Optional fields are **omitted when empty** at serialization time
/// ([toRecord]), in the canonical key order
/// `id, role, rect, label?, identifier?, value?, state?, actions?, scroll?`.
@immutable
class NativeNode {
  /// Records one perceived node. [id]/[role]/[rect] are always present; the
  /// rest are optional. [a11yId] is the OS accessibility identifier — used as
  /// resolver tier 1 AND surfaced on the wire as `identifier` (the stable,
  /// locale-proof addressing key, mirroring Flutter's `Semantics(identifier:)`).
  /// [xpath] stays selector-internal (never wired).
  const NativeNode({
    required this.id,
    required this.role,
    this.label,
    this.value,
    required this.rect,
    this.state = const <String>[],
    this.actions = const <String>[],
    this.scroll,
    this.a11yId,
    this.xpath,
  });

  /// Dense per-session int (NOT the raw a11y-id).
  final int id;

  /// Flutter-vocab role, e.g. `button`/`textfield`/`link`/`text`.
  final String role;

  /// Visible label (falls back to the a11y name when the label is empty).
  final String? label;

  /// Text-field contents / element value (masked bullets for a secure field).
  final String? value;

  /// `[left, top, right, bottom]` device-space ints.
  final List<int> rect;

  /// Carried for schema parity with Flutter; empty in m2 iOS.
  final List<String> state;

  /// Available actions (best-effort; may be empty in m2 iOS).
  final List<String> actions;

  /// Carried for schema parity with Flutter; null in m2 iOS.
  final Map<String, Object?>? scroll;

  /// Raw OS accessibility identifier — selector tier 1, and the source of the
  /// wire `identifier` field ([toRecord]). On iOS this is what
  /// `Semantics(identifier:)` lowers to, giving the brain the same stable,
  /// locale-proof addressing key on the native channel as on Flutter.
  final String? a11yId;

  /// Node's synthesized/derived XPath — selector tier 3.
  final String? xpath;

  /// Emits the canonical cross-host record, matching the Flutter `_Rec.toJson`
  /// key order EXACTLY: `id`/`role`/`rect` always present;
  /// `label`/`identifier`/`value`/`state`/`actions`/`scroll` OMITTED when
  /// null/empty. `identifier` carries [a11yId] (the stable addressing key);
  /// `xpath` is NOT emitted to the wire (selector-internal) and lives on the
  /// in-memory node only.
  Map<String, Object?> toRecord() {
    final Map<String, Object?> m = <String, Object?>{
      'id': id,
      'role': role,
      'rect': rect,
    };
    if (label != null && label!.isNotEmpty) m['label'] = label;
    if (a11yId != null && a11yId!.isNotEmpty) m['identifier'] = a11yId;
    if (value != null && value!.isNotEmpty) m['value'] = value;
    if (state.isNotEmpty) m['state'] = state;
    if (actions.isNotEmpty) m['actions'] = actions;
    if (scroll != null) m['scroll'] = scroll;
    return m;
  }
}

/// A point-in-time snapshot of the native app's flattened a11y tree.
@immutable
class NativeSnapshot {
  /// Records the [platform] (`ios`/`android`) and the flattened [nodes] in
  /// document order.
  const NativeSnapshot({required this.platform, required this.nodes});

  /// `ios` | `android`.
  final String platform;

  /// Flattened a11y tree, in document order.
  final List<NativeNode> nodes;
}
