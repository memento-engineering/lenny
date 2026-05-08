import 'package:exploration_agent/exploration_agent.dart'
    show PluginManifestEntry;
import 'package:flutter/material.dart';

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

class ExplorationShell extends StatelessWidget {
  const ExplorationShell({
    super.key,
    required this.vmServiceUri,
    this.availableModels = _defaultAvailableModels,
    this.plugins = const [],
  });

  /// Resolves the VM service URI for [ExplorationPanelHost]. Production passes
  /// `() => serviceManager.serviceUri`; tests pass a stub.
  final VmServiceUriResolver vmServiceUri;

  /// Models offered in the prompt panel's dropdown.
  final List<ModelDescriptor> availableModels;

  /// Plugin manifest from the binding handshake (cx6.11). Empty list
  /// renders the empty-state hint.
  final List<PluginManifestEntry> plugins;

  @override
  Widget build(BuildContext context) => ExplorationPanelHost(
        vmServiceUri: vmServiceUri,
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
                PromptTabMount(
                  availableModels: availableModels,
                  plugins: plugins,
                ),
                const ThinkingPlaceholder(),
                const TimelinePanelMount(),
              ],
            ),
          ),
        ),
      );
}
