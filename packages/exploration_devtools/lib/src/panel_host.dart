import 'package:exploration_agent/exploration_agent.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'manifest_probe.dart';

/// Returns the VM service URI to which DevTools is currently connected.
///
/// Production wires this to `serviceManager.serviceUri` from
/// `package:devtools_extensions`. Tests can pass a stub.
typedef VmServiceUriResolver = String? Function();

/// In-panel host that owns a single [ExplorationSession] for the extension.
/// Sub-panels reach it via [ExplorationPanelHost.of].
class ExplorationPanelHost extends StatefulWidget {
  const ExplorationPanelHost({
    super.key,
    required this.child,
    required this.vmServiceUri,
    this.manifestProbe = defaultManifestProbe,
  });

  final Widget child;

  /// Resolves the active VM service URI on demand. Decoupled from
  /// `serviceManager` so this widget compiles in pure-VM widget tests
  /// (the DevTools globals depend on `package:web` JS interop).
  final VmServiceUriResolver vmServiceUri;

  /// Probes the binding handshake to load the active plugin manifest.
  /// Defaults to [defaultManifestProbe]; tests inject a stub.
  final ManifestProbe manifestProbe;

  static ExplorationPanelHostState of(BuildContext context) =>
      context.findAncestorStateOfType<ExplorationPanelHostState>()!;

  @override
  State<ExplorationPanelHost> createState() => ExplorationPanelHostState();
}

class ExplorationPanelHostState extends State<ExplorationPanelHost> {
  ExplorationSession? _session;

  final ValueNotifier<ManifestProbeResult> _manifest =
      ValueNotifier<ManifestProbeResult>(const ManifestProbeLoading());

  /// Monotonically increasing counter used to drop stale probe results
  /// (the latest call to [refreshManifest] is the only one allowed to
  /// publish).
  int _probeGen = 0;

  ExplorationSession? get session => _session;

  /// Latest manifest probe state. Sub-panels listen via
  /// `ValueListenableBuilder` to react to (re)connects.
  ValueListenable<ManifestProbeResult> get manifest => _manifest;

  @override
  void initState() {
    super.initState();
    // Kick off the initial probe. Errors are translated to sealed
    // variants inside refreshManifest, so this fire-and-forget is safe.
    // ignore: unawaited_futures
    refreshManifest();
  }

  /// Re-run the manifest probe.
  ///
  /// Publishes [ManifestProbeLoading] immediately, then either
  /// [ManifestProbeLoaded], [ManifestProbeBindingMissing] (if the binding
  /// extension is absent or the VM service URI is missing), or
  /// [ManifestProbeFailed]. Stale results from earlier invocations are
  /// dropped via [_probeGen].
  Future<void> refreshManifest() async {
    final raw = widget.vmServiceUri();
    final gen = ++_probeGen;
    _manifest.value = const ManifestProbeLoading();
    if (raw == null) {
      if (gen == _probeGen && mounted) {
        _manifest.value = const ManifestProbeBindingMissing();
      }
      return;
    }
    try {
      final plugins = await widget.manifestProbe(Uri.parse(raw));
      if (gen != _probeGen || !mounted) return;
      _manifest.value = ManifestProbeLoaded(plugins);
    } on BindingNotInitializedError {
      if (gen != _probeGen || !mounted) return;
      _manifest.value = const ManifestProbeBindingMissing();
    } catch (e) {
      if (gen != _probeGen || !mounted) return;
      _manifest.value = ManifestProbeFailed(e.toString());
    }
  }

  Future<ExplorationSession> ensureSession() async {
    final existing = _session;
    if (existing != null) return existing;
    final uri = widget.vmServiceUri();
    if (uri == null) {
      throw StateError('VM service unavailable');
    }
    final created = await ExplorationSession.connect(Uri.parse(uri));
    if (!mounted) {
      await created.end();
      throw StateError('Panel host disposed during connect');
    }
    setState(() => _session = created);
    return created;
  }

  Future<void> endSession() async {
    final s = _session;
    if (s == null) return;
    await s.end();
    if (!mounted) return;
    setState(() => _session = null);
  }

  @override
  void dispose() {
    _session?.end();
    _manifest.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
