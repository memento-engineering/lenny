import 'package:flutter/material.dart';

import 'manifest_probe.dart';
import 'panel_host.dart';
import 'panels/prompt_panel_config.dart';
import 'panels/prompt_tab_mount.dart';
import 'panels/thinking_placeholder.dart';
import 'panels/timeline_panel_mount.dart';

/// The visible content of the extension: panel host + tabbed Scaffold.
///
/// Split out from `ExplorationDevToolsExtension` so widget tests can pump it
/// without triggering `DevToolsExtension`'s browser-only initialization.
/// Default model surfaced in the prompt-panel dropdown until cx6.14/.15/.16
/// wire real provider lists into the shell. Lives in the shell file so
/// `prompt_panel.dart` stays free of hardcoded ids (cx6.22 AC7).
const List<ModelDescriptor> _defaultAvailableModels = [
  ModelDescriptor(id: 'default', label: 'Default'),
];

/// Tabbed shell for the Exploration DevTools extension. Drives the Prompt
/// tab off the live manifest probe owned by [ExplorationPanelHost].
class ExplorationShell extends StatefulWidget {
  const ExplorationShell({
    super.key,
    required this.vmServiceUri,
    this.availableModels = _defaultAvailableModels,
    this.vmServiceUriListenable,
    this.manifestProbe,
  });

  /// Resolves the VM service URI for [ExplorationPanelHost]. Production passes
  /// `() => serviceManager.serviceUri`; tests pass a stub.
  final VmServiceUriResolver vmServiceUri;

  /// Models offered in the prompt panel's dropdown.
  final List<ModelDescriptor> availableModels;

  /// Optional listenable that, when it fires, triggers a fresh probe.
  /// Production wires `serviceManager.connectedState` so reconnects re-load
  /// the plugin manifest.
  final Listenable? vmServiceUriListenable;

  /// Override for the manifest probe. Tests inject a stub; production
  /// leaves this null and the host uses `defaultManifestProbe`.
  final ManifestProbe? manifestProbe;

  @override
  State<ExplorationShell> createState() => _ExplorationShellState();
}

class _ExplorationShellState extends State<ExplorationShell> {
  final GlobalKey<ExplorationPanelHostState> _hostKey =
      GlobalKey<ExplorationPanelHostState>();

  @override
  void initState() {
    super.initState();
    widget.vmServiceUriListenable?.addListener(_onUriChanged);
  }

  @override
  void didUpdateWidget(covariant ExplorationShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vmServiceUriListenable != widget.vmServiceUriListenable) {
      oldWidget.vmServiceUriListenable?.removeListener(_onUriChanged);
      widget.vmServiceUriListenable?.addListener(_onUriChanged);
    }
  }

  @override
  void dispose() {
    widget.vmServiceUriListenable?.removeListener(_onUriChanged);
    super.dispose();
  }

  void _onUriChanged() {
    // ignore: unawaited_futures
    _hostKey.currentState?.refreshManifest();
  }

  @override
  Widget build(BuildContext context) {
    final host = ExplorationPanelHost(
      key: _hostKey,
      vmServiceUri: widget.vmServiceUri,
      manifestProbe: widget.manifestProbe ?? defaultManifestProbe,
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
                availableModels: widget.availableModels,
              ),
              const ThinkingPlaceholder(),
              const TimelinePanelMount(),
            ],
          ),
        ),
      ),
    );
    return host;
  }
}

/// Renders the Prompt tab off the host's `ValueListenable<ManifestProbeResult>`.
class _PromptTabBody extends StatelessWidget {
  const _PromptTabBody({
    required this.hostKey,
    required this.availableModels,
  });

  final GlobalKey<ExplorationPanelHostState> hostKey;
  final List<ModelDescriptor> availableModels;

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
              availableModels: availableModels,
              plugins: plugins,
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
