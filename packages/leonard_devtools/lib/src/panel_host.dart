import 'package:leonard_agent/leonard_agent.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'manifest_probe.dart';
import 'panels/prompt_panel_controller.dart' show SessionFactory;

/// In-panel host that owns a single [LeonardSession] for the extension.
/// Sub-panels reach it via [LeonardPanelHost.of].
///
/// The host no longer plumbs a VM service `Uri`: the DevTools wiring
/// (`leonard_shell.dart` / `main.dart`) supplies a [manifestProbe]
/// and a [sessionFactory] that close over `serviceManager.service`, so
/// this widget stays free of `serviceManager` (and `dart:io`) and still
/// compiles in pure-VM widget tests.
class LeonardPanelHost extends StatefulWidget {
  const LeonardPanelHost({
    super.key,
    required this.child,
    required this.manifestProbe,
    required this.sessionFactory,
  });

  final Widget child;

  /// Loads the active extension manifest by running the binding handshake.
  /// Production wires a closure over `serviceManager.service`; tests
  /// inject a stub.
  final ManifestProbe manifestProbe;

  /// Builds the in-panel [LeonardSession]. Production wires a closure
  /// over `serviceManager.service` + the main isolate id (via
  /// [LeonardSession.fromVmService]); tests inject a stub. (The CLI
  /// frontend, which runs on the Dart VM, uses the dart:io connect path
  /// instead — it never goes through this widget.)
  final SessionFactory sessionFactory;

  static LeonardPanelHostState of(BuildContext context) =>
      context.findAncestorStateOfType<LeonardPanelHostState>()!;

  @override
  State<LeonardPanelHost> createState() => LeonardPanelHostState();
}

class LeonardPanelHostState extends State<LeonardPanelHost> {
  LeonardSession? _session;

  final ValueNotifier<ManifestProbeResult> _manifest =
      ValueNotifier<ManifestProbeResult>(const ManifestProbeLoading());

  final ValueNotifier<LeonardSession?> _sessionNotifier =
      ValueNotifier<LeonardSession?>(null);

  /// Monotonically increasing counter used to drop stale probe results
  /// (the latest call to [refreshManifest] is the only one allowed to
  /// publish).
  int _probeGen = 0;

  LeonardSession? get session => _session;

  /// Listenable that fires whenever the active session changes.
  /// Sub-panels should use [ValueListenableBuilder] on this to rebuild
  /// reactively (e.g. [TranscriptList] via [ConversationViewModel]).
  ValueListenable<LeonardSession?> get sessionListenable => _sessionNotifier;

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
  /// [ManifestProbeLoaded], [ManifestProbeBindingMissing] (if the probe
  /// throws `BindingNotInitializedError` — extension absent or no VM
  /// service / isolate available), or [ManifestProbeFailed]. Stale
  /// results from earlier invocations are dropped via [_probeGen].
  Future<void> refreshManifest() async {
    final gen = ++_probeGen;
    _manifest.value = const ManifestProbeLoading();
    try {
      final extensions = await widget.manifestProbe();
      if (gen != _probeGen || !mounted) return;
      _manifest.value = ManifestProbeLoaded(extensions);
    } on BindingNotInitializedError {
      if (gen != _probeGen || !mounted) return;
      _manifest.value = const ManifestProbeBindingMissing();
    } catch (e) {
      if (gen != _probeGen || !mounted) return;
      _manifest.value = ManifestProbeFailed(e.toString());
    }
  }

  Future<LeonardSession> ensureSession() async {
    final existing = _session;
    if (existing != null) return existing;
    final created = await widget.sessionFactory();
    if (!mounted) {
      await created.end();
      throw StateError('Panel host disposed during connect');
    }
    setState(() => _session = created);
    _sessionNotifier.value = created;
    return created;
  }

  Future<void> endSession() async {
    final s = _session;
    if (s == null) return;
    await s.end();
    if (!mounted) return;
    setState(() => _session = null);
    _sessionNotifier.value = null;
  }

  @override
  void dispose() {
    _session?.end();
    _manifest.dispose();
    _sessionNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
