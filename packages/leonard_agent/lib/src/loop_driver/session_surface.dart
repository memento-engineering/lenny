/// The minimal session surface the loop driver depends on.
///
/// Extracted (m3, `lenny-qxx.3`) so the brain loop is agnostic to whether
/// it drives a single-host [LeonardSession] or a multi-host
/// `MultiHostSession`. Both implement this; `DefaultLoopHost` and
/// `bringUpSession` are typed against it, not against the concrete session.
///
/// Pure and io-free: it names only `package:leonard_agent` value types
/// ([HandshakeResult], [Observation], [StabilityPolicy]). The underlying
/// `VmServiceClient` is deliberately NOT exposed here — actions route
/// through [executeAction] so a multi-host session can dispatch each
/// `<namespace>.<tool>` to the owning host.
library;

import '../observation/models.dart';
import '../session/observation_puller.dart';
import '../types.dart';

/// The contract the loop driver's host adapter relies on.
abstract class SessionSurface {
  /// The merged handshake (manifest + capabilities + contract version).
  /// For a single host this is that host's handshake; for a multi-host
  /// session it is the union across hosts. Throws [StateError] before
  /// `start()` completes.
  HandshakeResult get handshake;

  /// Pull a stable observation. For a multi-host session this is the
  /// merged observation (every host's namespaced fragment, side by side).
  Future<Observation> pullObservation({StabilityPolicy policy});

  /// Execute a `<namespace>.<tool>` action. A multi-host session routes
  /// it to the owning host; a single-host session forwards to its client.
  Future<Map<String, dynamic>> executeAction(
    String tool,
    Map<String, dynamic> args,
  );

  /// Record an auto-disable for [namespace] with a human-readable [reason].
  void disableExtension(String namespace, String reason);
}
