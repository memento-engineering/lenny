import 'package:exploration_agent/exploration_agent.dart';
import 'package:flutter/material.dart';

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
  });

  final Widget child;

  /// Resolves the active VM service URI on demand. Decoupled from
  /// `serviceManager` so this widget compiles in pure-VM widget tests
  /// (the DevTools globals depend on `package:web` JS interop).
  final VmServiceUriResolver vmServiceUri;

  static ExplorationPanelHostState of(BuildContext context) =>
      context.findAncestorStateOfType<ExplorationPanelHostState>()!;

  @override
  State<ExplorationPanelHost> createState() => ExplorationPanelHostState();
}

class ExplorationPanelHostState extends State<ExplorationPanelHost> {
  ExplorationSession? _session;

  ExplorationSession? get session => _session;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
