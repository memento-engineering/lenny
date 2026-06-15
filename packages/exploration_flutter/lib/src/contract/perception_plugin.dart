library;

import 'package:genesis_perception/genesis_perception.dart';

import 'plugin.dart';

/// Marks an [ExplorationPlugin] as the sole observation surface for its
/// namespace. The binding's single observation loop emits a
/// `plugins.<namespace>` fragment for every registered plugin that mixes
/// this in (subject to [isPerceptionIdle]); plugins that do NOT mix it in
/// contribute no fragment (mirroring the retired `observe() => null`).
///
/// The two non-build members below relocate behaviors the retired
/// `observe()` method silently provided:
///
/// * [isPerceptionIdle] reproduces the old `observe() == null` suppression
///   — when it returns `true`, the binding skips this namespace entirely.
/// * [prepareForObservation] is the pre-build side-effect seam that used to
///   live inside `observe()` (e.g. riverpod's `flushPendingAt`). The binding
///   calls it BEFORE [isPerceptionIdle] and [buildPerception] each turn.
mixin PerceptionPlugin on ExplorationPlugin {
  /// Build the perception tree serialized into this plugin's fragment.
  Seed buildPerception();

  /// Whether the plugin has nothing to contribute this turn. When `true`,
  /// the binding emits no `plugins.<namespace>` fragment — the exact
  /// suppression the retired `observe() => null` provided. Defaults to
  /// `false` (always contribute). Evaluated AFTER [prepareForObservation].
  bool isPerceptionIdle() => false;

  /// Pre-build side-effect hook, called by the binding immediately before
  /// [isPerceptionIdle] and [buildPerception] each observation turn. This
  /// relocates side effects that used to run inside `observe()` (e.g.
  /// draining a pending-change ring). Defaults to a no-op.
  void prepareForObservation() {}
}
