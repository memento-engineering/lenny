import 'package:flutter/material.dart';

import 'panel_host.dart';
import 'panels/prompt_placeholder.dart';
import 'panels/thinking_placeholder.dart';
import 'panels/timeline_placeholder.dart';

/// The visible content of the extension: panel host + tabbed Scaffold.
///
/// Split out from `ExplorationDevToolsExtension` so widget tests can pump it
/// without triggering `DevToolsExtension`'s browser-only initialization.
class ExplorationShell extends StatelessWidget {
  const ExplorationShell({super.key, required this.vmServiceUri});

  /// Resolves the VM service URI for [ExplorationPanelHost]. Production passes
  /// `() => serviceManager.serviceUri`; tests pass a stub.
  final VmServiceUriResolver vmServiceUri;

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
            body: const TabBarView(
              children: [
                PromptPlaceholder(),
                ThinkingPlaceholder(),
                TimelinePlaceholder(),
              ],
            ),
          ),
        ),
      );
}
