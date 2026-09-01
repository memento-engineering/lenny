/// Single-call typed observation puller.
///
/// Wraps [VmServiceClient.callExtension] to make exactly one VM-service
/// call to `ext.leonard.core.get_stable_observation`
/// and deserializes the response into a typed [Observation].
///
/// Stays internal to `package:leonard_agent` — only the public
/// [StabilityPolicy] enum is exported. Consumers reach the puller
/// indirectly via [LeonardSession.observeWithDiff].
library;

import 'package:leonard_contract/leonard_contract.dart';

import '../errors.dart';
import '../observation/models.dart';
import '../vm_service_client.dart';

/// Service-extension method we invoke (PRD §10 step 4).
const String _kExtGetStableObservation =
    '$kLeonardExtensionPrefix.core.get_stable_observation';

/// Wire-name mapping for the request's `policy` parameter. Mirrors
/// `kStabilityPolicyWireNames` on the binding side
/// (`packages/leonard_flutter/.../observation_request.dart`).
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
/// Constructed by [LeonardSession]. One [pull] call corresponds to
/// exactly one VM-service round-trip.
class ObservationPuller {
  ObservationPuller(this._client);

  final VmServiceClient _client;

  /// Issues one `get_stable_observation` call and returns the raw response
  /// map, undecoded. This lets diagnostic capture share an already-pinned
  /// session connection instead of opening a second VM-service client.
  Future<Map<String, dynamic>> pullRaw({
    StabilityPolicy policy = StabilityPolicy.actionRelative,
    int? coreBudgetBytes,
  }) => _client.callExtension(_kExtGetStableObservation, <String, dynamic>{
    'policy': policy.wireName,
    // developer.registerExtension supplies a Map<String, String>; the
    // binding parses numeric request values from their string form.
    if (coreBudgetBytes != null) 'coreBudgetBytes': '$coreBudgetBytes',
  });

  /// Issues a single `get_stable_observation` call and returns the typed
  /// [Observation]. Accepts the Flutter binding's core envelope and the
  /// pure-Dart host's tools-only envelope. The top-level `type` belongs to
  /// the transport and is deliberately ignored because DWDS rewrites it.
  Future<Observation> pull({
    StabilityPolicy policy = StabilityPolicy.actionRelative,
    int? coreBudgetBytes,
  }) async {
    final Map<String, dynamic> resp = await pullRaw(
      policy: policy,
      coreBudgetBytes: coreBudgetBytes,
    );
    final Object? wrapped = resp['value'];
    if (wrapped is! Map ||
        (wrapped['semantics'] is! List && wrapped['extensions'] is! Map)) {
      throw ObservationEnvelopeError(
        isolateId: _client.isolateId,
        topLevelKeys: resp.keys,
      );
    }
    return Observation.fromJson(wrapped.cast<String, dynamic>());
  }
}
