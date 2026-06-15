import 'observation_request.dart';

/// Termination reason recorded in the response under
/// `stability.terminated_by` (PRD §9.2).
enum TerminatedBy { routeChange, semanticsChange, idle, quietFrame, budget }

/// Wire mapping for [TerminatedBy] values.
const Map<TerminatedBy, String> kTerminatedByWireNames =
    <TerminatedBy, String>{
  TerminatedBy.routeChange: 'route_change',
  TerminatedBy.semanticsChange: 'semantics_change',
  TerminatedBy.idle: 'idle',
  TerminatedBy.quietFrame: 'quiet_frame',
  TerminatedBy.budget: 'budget',
};

/// Per-plugin busy descriptor included in the response's
/// `stability.extensions_busy[]` list (PRD §9.2).
class ExtensionBusy {
  const ExtensionBusy(this.namespace, {this.reason, this.estMs});

  /// Plugin namespace (matches its registry namespace).
  final String namespace;

  /// Optional human-readable reason from `BusyState.reason`.
  final String? reason;

  /// Optional estimate (ms) from `BusyState.estimatedDuration`.
  final int? estMs;

  Map<String, Object?> toJson() {
    final Map<String, Object?> m = <String, Object?>{'namespace': namespace};
    if (reason != null) m['reason'] = reason;
    if (estMs != null) m['est_ms'] = estMs;
    return m;
  }
}

/// Stability metadata block carried in the `stability` key of every
/// response from `getStableObservation` (PRD §9.2).
class StabilityMetadata {
  const StabilityMetadata({
    required this.policy,
    required this.terminatedBy,
    required this.durationMs,
    required this.frameworkBusy,
    required this.extensionsBusy,
  });

  /// Selected policy (echoes the request).
  final StabilityPolicy policy;

  /// Termination reason for the observation loop.
  final TerminatedBy terminatedBy;

  /// Wall-clock duration the policy loop ran for, in ms.
  final int durationMs;

  /// Verbatim JSON projection of the cx6.4 framework busy snapshot.
  final Map<String, Object?> frameworkBusy;

  /// Plugins that reported `BusyState.isBusy == true` at termination.
  /// For `idle` / `quiet_frame` terminations this is empty by
  /// construction (the loop only stops once everyone is idle).
  final List<ExtensionBusy> extensionsBusy;

  Map<String, Object?> toJson() => <String, Object?>{
        'policy': kStabilityPolicyWireNames[policy],
        'terminated_by': kTerminatedByWireNames[terminatedBy],
        'duration_ms': durationMs,
        'framework_busy': frameworkBusy,
        'extensions_busy':
            extensionsBusy.map((ExtensionBusy p) => p.toJson()).toList(),
      };
}
