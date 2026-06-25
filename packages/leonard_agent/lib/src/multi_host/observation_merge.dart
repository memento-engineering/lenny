/// Pure observation merge for the multi-host harness (m3, `lenny-qxx.3`).
///
/// Folds N per-host [Observation]s into one merged observation whose
/// `extensions` map is the side-by-side union of every host's namespaced
/// fragment. The merge is a **synchronous pure function** — no async, no
/// I/O (genesis ADR-0006, pull-free build): the caller (`MultiHostSession`)
/// gathers each host's observation out-of-band (`Future.wait` of the
/// per-host pullers) and then calls this on the already-resolved values.
///
/// Inputs are assumed namespace-disjoint: `MultiHostSession.start` runs the
/// namespace-collision check at handshake time, so by the time observations
/// are merged no two hosts share a namespace key. This function therefore
/// throws nothing and overwrites nothing.
library;

import '../observation/models.dart';

/// Merge [perHost] observations (in attach order, primary/Flutter first)
/// into one [Observation]:
///
/// * `core` — the FIRST non-empty `core` in attach order. With today's
///   hosts only the Flutter (primary) host populates `core`; the pure-Dart
///   native host's `core` is empty. Falls back to the primary's `core`.
/// * `extensions` — the union of every host's `extensions` map, keyed by
///   namespace (disjoint, so nothing is overwritten or conflated).
/// * `stability` — `policy`/`terminatedBy`/`durationMs`/`frameworkBusy`
///   taken from the PRIMARY (first) host verbatim; `extensionsBusy`
///   CONCATENATED across all hosts (each entry is already namespaced via
///   [ExtensionBusy.namespace], so a native busy signal rides this list
///   alongside Flutter's). There is no `frameworkBusy` union.
/// * `screenshot` — the PRIMARY host's screenshot when present (the native
///   host exposes no screenshot in m3).
///
/// Throws [ArgumentError] if [perHost] is empty (a session always attaches
/// at least one host).
Observation mergeObservations(List<Observation> perHost) {
  if (perHost.isEmpty) {
    throw ArgumentError.value(
      perHost,
      'perHost',
      'mergeObservations requires at least one observation',
    );
  }
  final Observation primary = perHost.first;

  // core: first non-empty in attach order, else the primary's (empty) core.
  CoreFragment mergedCore = primary.core;
  for (final Observation o in perHost) {
    if (o.core != CoreFragment.empty) {
      mergedCore = o.core;
      break;
    }
  }

  // extensions: disjoint union across hosts, in attach order.
  final Map<String, ExtensionFragment> mergedExtensions =
      <String, ExtensionFragment>{};
  for (final Observation o in perHost) {
    mergedExtensions.addAll(o.extensions);
  }

  // stability: framework fields from primary verbatim; extensionsBusy
  // concatenated across all hosts (primary first).
  final List<ExtensionBusy> mergedBusy = <ExtensionBusy>[
    for (final Observation o in perHost) ...o.stability.extensionsBusy,
  ];
  final StabilityMetadata mergedStability = StabilityMetadata(
    policy: primary.stability.policy,
    terminatedBy: primary.stability.terminatedBy,
    durationMs: primary.stability.durationMs,
    frameworkBusy: primary.stability.frameworkBusy,
    extensionsBusy: List<ExtensionBusy>.unmodifiable(mergedBusy),
  );

  return Observation(
    core: mergedCore,
    extensions: Map<String, ExtensionFragment>.unmodifiable(mergedExtensions),
    stability: mergedStability,
    screenshot: primary.screenshot,
  );
}
