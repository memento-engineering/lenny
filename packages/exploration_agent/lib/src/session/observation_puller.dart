/// Single-call typed observation puller.
///
/// Wraps [VmServiceClient.callExtension] to make exactly one VM-service
/// call to `ext.exploration.core.get_stable_observation` (cx6.8)
/// and deserializes the response into a typed [Observation] (cx6.12).
///
/// Stays internal to `package:exploration_agent` — only the public
/// [StabilityPolicy] enum is exported. Consumers reach the puller
/// indirectly via [ExplorationSession.observeWithDiff].
library;

import '../observation/models.dart';
import '../vm_service_client.dart';

/// Service-extension method we invoke (PRD §10 step 4, cx6.8).
const String _kExtGetStableObservation =
    'ext.exploration.core.get_stable_observation';

/// Wire-name mapping for the request's `policy` parameter. Mirrors
/// `kStabilityPolicyWireNames` on the binding side
/// (`packages/exploration_flutter/.../observation_request.dart`).
enum StabilityPolicy {
  /// Default policy: end after route/semantics change, all-idle, or the
  /// per-action budget.
  actionRelative('action-relative'),

  /// Stop after N consecutive idle frames.
  quietFrame('quiet-frame'),

  /// Hybrid: quiet-frame OR a wall-clock budget; tags `budget` on
  /// timeout.
  boundedStability('bounded-stability');

  const StabilityPolicy(this.wireName);

  /// Kebab-case wire identifier sent in the request payload — matches
  /// `kStabilityPolicyWireNames` on the binding side (PRD §9.1).
  final String wireName;
}

/// Typed wrapper for `get_stable_observation`.
///
/// Constructed by [ExplorationSession]. One [pull] call corresponds to
/// exactly one VM-service round-trip.
class ObservationPuller {
  ObservationPuller(this._client);

  final VmServiceClient _client;

  /// Issues a single `get_stable_observation` call and returns the typed
  /// [Observation]. The binding wraps the bundle as
  /// `{type: 'Observation', value: <bundle>}`; we unwrap that envelope
  /// before deserializing.
  Future<Observation> pull({
    StabilityPolicy policy = StabilityPolicy.actionRelative,
  }) async {
    final Map<String, dynamic> resp = await _client.callExtension(
      _kExtGetStableObservation,
      <String, dynamic>{'policy': policy.wireName},
    );
    final Object? wrapped = resp['value'];
    final Map<String, dynamic> bundle = wrapped is Map
        ? wrapped.cast<String, dynamic>()
        : resp;
    return Observation.fromJson(bundle);
  }
}
