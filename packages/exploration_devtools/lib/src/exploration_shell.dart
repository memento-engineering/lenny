import 'package:exploration_agent/exploration_agent.dart'
    show TrajectoryRecord;
import 'package:flutter/material.dart';

import 'manifest_probe.dart';
import 'panel_host.dart';
import 'panels/model_catalog.dart';
import 'panels/prompt_panel_config_store.dart';
import 'panels/prompt_panel_controller.dart'
    show PromptPanelController, SessionFactory;
import 'panels/prompt_tab_mount.dart';
import 'panels/provider_config_store.dart';
import 'panels/thinking_placeholder.dart';
import 'panels/timeline_panel_mount.dart';

/// The visible content of the extension: panel host + tabbed Scaffold.
///
/// Split out from `ExplorationDevToolsExtension` so widget tests can pump
/// it without triggering `DevToolsExtension`'s browser-only
/// initialization.
///
/// The shell owns one [ProviderConfigStore] and one [ModelCatalog] — the
/// prompt-panel mount layer consumes both. Tests can pass an in-memory
/// store; production wires a [DtdProviderConfigStore]. The shell also
/// drives the Prompt tab off the live manifest probe owned by
/// [ExplorationPanelHost], so plugin toggles reflect the connected app.
///
/// The shell is `serviceManager`-free: `main.dart` builds [manifestProbe]
/// and [sessionFactory] as closures over `serviceManager.service`, so
/// pure-VM widget tests can pump the shell without the DevTools globals.
class ExplorationShell extends StatefulWidget {
  ExplorationShell({
    super.key,
    required this.manifestProbe,
    required this.sessionFactory,
    this.probeRetrigger,
    ProviderConfigStore? store,
    ModelCatalog? catalog,
    PromptPanelConfigStore? promptConfigStore,
  })  : store = store ?? InMemoryProviderConfigStore(),
        catalog = catalog ?? ModelCatalog(),
        promptConfigStore =
            promptConfigStore ?? InMemoryPromptPanelConfigStore();

  /// Loads the active plugin manifest for [ExplorationPanelHost].
  /// Production wires a closure over `serviceManager.service` + the main
  /// isolate id (built on [probeManifest]); tests pass a stub.
  final ManifestProbe manifestProbe;

  /// Builds the in-panel [ExplorationSession]. Production wires a closure
  /// over `serviceManager.service` + the main isolate id (via
  /// [ExplorationSession.fromVmService]); tests pass a stub.
  final SessionFactory sessionFactory;

  /// Optional listenable that, when it fires, triggers a fresh probe.
  /// Production wires `Listenable.merge([serviceManager.connectedState,
  /// serviceManager.isolateManager.mainIsolate])` so reconnects re-load
  /// the plugin manifest.
  final Listenable? probeRetrigger;

  /// Per-provider config persistence.
  final ProviderConfigStore store;

  /// Shared model catalog.
  final ModelCatalog catalog;

  /// Persists and restores last-used prompt form state across reloads.
  final PromptPanelConfigStore promptConfigStore;

  @override
  State<ExplorationShell> createState() => _ExplorationShellState();
}

class _ExplorationShellState extends State<ExplorationShell> {
  final GlobalKey<ExplorationPanelHostState> _hostKey =
      GlobalKey<ExplorationPanelHostState>();

  /// Holds the controller's live trajectory stream once the prompt
  /// tab starts a session. The Timeline tab reads through this so
  /// records the loop emits during a run are rendered in real time.
  final ValueNotifier<Stream<TrajectoryRecord>?> _trajectory =
      ValueNotifier<Stream<TrajectoryRecord>?>(null);

  @override
  void initState() {
    super.initState();
    widget.probeRetrigger?.addListener(_onRetrigger);
  }

  @override
  void didUpdateWidget(covariant ExplorationShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.probeRetrigger != widget.probeRetrigger) {
      oldWidget.probeRetrigger?.removeListener(_onRetrigger);
      widget.probeRetrigger?.addListener(_onRetrigger);
    }
  }

  @override
  void dispose() {
    widget.probeRetrigger?.removeListener(_onRetrigger);
    _trajectory.dispose();
    super.dispose();
  }

  void _onRetrigger() {
    // ignore: unawaited_futures
    _hostKey.currentState?.refreshManifest();
  }

  @override
  Widget build(BuildContext context) {
    return ExplorationPanelHost(
      key: _hostKey,
      manifestProbe: widget.manifestProbe,
      sessionFactory: widget.sessionFactory,
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Exploration'),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Prompt'),
                Tab(text: 'Thinking'),
                Tab(text: 'Timeline'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _PromptTabBody(
                hostKey: _hostKey,
                store: widget.store,
                catalog: widget.catalog,
                promptConfigStore: widget.promptConfigStore,
                trajectorySink: _trajectory,
              ),
              const ThinkingPlaceholder(),
              ValueListenableBuilder<Stream<TrajectoryRecord>?>(
                valueListenable: _trajectory,
                builder: (context, stream, _) =>
                    TimelinePanelMount(trajectoryStream: stream),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders the Prompt tab off the host's `ValueListenable<ManifestProbeResult>`.
///
/// On `Loaded`, builds the real [PromptTabMount] wired to the shell's
/// shared [ProviderConfigStore] + [ModelCatalog]; on `Loading` /
/// `BindingMissing` / `Failed`, surfaces the corresponding status.
class _PromptTabBody extends StatelessWidget {
  const _PromptTabBody({
    required this.hostKey,
    required this.store,
    required this.catalog,
    required this.promptConfigStore,
    required this.trajectorySink,
  });

  final GlobalKey<ExplorationPanelHostState> hostKey;
  final ProviderConfigStore store;
  final ModelCatalog catalog;
  final PromptPanelConfigStore promptConfigStore;

  /// Write-side seam — the prompt tab assigns the controller's live
  /// trajectory stream here when a session starts; the Timeline tab
  /// reads through this notifier.
  final ValueNotifier<Stream<TrajectoryRecord>?> trajectorySink;

  @override
  Widget build(BuildContext context) {
    // The host is an ancestor of this widget (we are inside its `child`),
    // so its State exists by the time this builds.
    final hostState = hostKey.currentState;
    if (hostState == null) {
      // Defensive: should not happen in normal mount order.
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<ManifestProbeResult>(
      valueListenable: hostState.manifest,
      builder: (context, result, _) {
        return switch (result) {
          ManifestProbeLoading() => const Center(
              child: CircularProgressIndicator(
                key: Key('prompt.manifestLoading'),
              ),
            ),
          ManifestProbeBindingMissing() => const _BindingMissingBanner(
              message:
                  'Binding not detected. Add ExplorationBinding.ensureInitialized() to your app\'s main().',
            ),
          ManifestProbeFailed(:final message) => _BindingMissingBanner(
              message: 'Binding not detected: $message',
            ),
          ManifestProbeLoaded(:final plugins) => PromptTabMount(
              plugins: plugins,
              store: store,
              catalog: catalog,
              promptConfigStore: promptConfigStore,
              controllerFactory: () => PromptPanelController(
                factory: hostState.ensureSession,
                onStop: hostState.endSession,
              ),
              trajectorySink: trajectorySink,
            ),
        };
      },
    );
  }
}

class _BindingMissingBanner extends StatelessWidget {
  const _BindingMissingBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        message,
        key: const Key('prompt.bindingNotDetected'),
      ),
    );
  }
}
