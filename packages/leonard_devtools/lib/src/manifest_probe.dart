/// Manifest probe types for the DevTools Prompt panel.
///
/// `LeonardPanelHost` resolves the plugin manifest by calling
/// `ext.exploration.handshake` through [VmServiceClient]. The shell
/// renders the result via a `ValueListenable<ManifestProbeResult>` so the
/// UI reacts to (re)connects without recreating the host.
library;

import 'package:leonard_agent/leonard_agent.dart'
    show ExtensionManifestEntry, VmServiceClient;
import 'package:vm_service/vm_service.dart' show VmService;

/// State of the latest manifest probe.
sealed class ManifestProbeResult {
  const ManifestProbeResult();
}

/// Probe is in flight; the panel renders a spinner.
class ManifestProbeLoading extends ManifestProbeResult {
  const ManifestProbeLoading();
}

/// Probe succeeded; [plugins] is the active plugin manifest (possibly empty).
class ManifestProbeLoaded extends ManifestProbeResult {
  const ManifestProbeLoaded(this.plugins);
  final List<ExtensionManifestEntry> plugins;
}

/// Probe could not run because the target app has no
/// `LeonardBinding` initialised (handshake extension absent).
class ManifestProbeBindingMissing extends ManifestProbeResult {
  const ManifestProbeBindingMissing();
}

/// Probe failed for some other reason — connection error, malformed
/// response, etc. [message] is the surfaced detail.
class ManifestProbeFailed extends ManifestProbeResult {
  const ManifestProbeFailed(this.message);
  final String message;
}

/// Function signature for loading the active plugin manifest. The
/// closure owns whatever connection it needs — production wires a
/// closure over `serviceManager.service` + the main isolate id (see
/// `main.dart`), built on top of [probeManifest]; tests inject a stub.
///
/// Throwing `BindingNotInitializedError` signals "no `LeonardBinding`
/// in the target" (→ [ManifestProbeBindingMissing]); any other throw is
/// surfaced as [ManifestProbeFailed].
typedef ManifestProbe = Future<List<ExtensionManifestEntry>> Function();

/// Run the binding handshake over an already-connected [vm] (pinned to
/// [isolateId]) and return the active plugin manifest.
///
/// Does **not** dispose [vm] — the DevTools extension owns that
/// connection via `serviceManager`. Errors propagate to the caller (the
/// host maps `BindingNotInitializedError` → [ManifestProbeBindingMissing]
/// and everything else → [ManifestProbeFailed]).
Future<List<ExtensionManifestEntry>> probeManifest(
  VmService vm,
  String isolateId,
) async {
  final client = VmServiceClient.fromVmService(vm, isolateId);
  final result = await client.handshake();
  return result.plugins;
}
