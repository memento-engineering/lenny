/// Manifest probe types for the DevTools Prompt panel.
///
/// `ExplorationPanelHost` resolves the plugin manifest by calling
/// `ext.flutter.exploration.handshake` through [VmServiceClient]. The shell
/// renders the result via a `ValueListenable<ManifestProbeResult>` so the
/// UI reacts to (re)connects without recreating the host.
library;

import 'package:exploration_agent/exploration_agent.dart'
    show PluginManifestEntry, VmServiceClient;

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
  final List<PluginManifestEntry> plugins;
}

/// Probe could not run because the target app has no
/// `ExplorationBinding` initialised (handshake extension absent).
class ManifestProbeBindingMissing extends ManifestProbeResult {
  const ManifestProbeBindingMissing();
}

/// Probe failed for some other reason — connection error, malformed
/// response, etc. [message] is the surfaced detail.
class ManifestProbeFailed extends ManifestProbeResult {
  const ManifestProbeFailed(this.message);
  final String message;
}

/// Function signature for running the handshake against a connected VM
/// service. Tests inject a stub; production wires [defaultManifestProbe].
typedef ManifestProbe =
    Future<List<PluginManifestEntry>> Function(Uri vmServiceUri);

/// Production probe: connect, handshake, dispose.
///
/// Connects to [uri] via [VmServiceClient.connect], reads the handshake's
/// plugin manifest, and disposes the connection. Errors propagate to the
/// caller (the host translates `BindingNotInitializedError` into
/// [ManifestProbeBindingMissing] and everything else into
/// [ManifestProbeFailed]).
Future<List<PluginManifestEntry>> defaultManifestProbe(Uri uri) async {
  final client = await VmServiceClient.connect(uri);
  try {
    final result = await client.handshake();
    return result.plugins;
  } finally {
    await client.dispose();
  }
}
