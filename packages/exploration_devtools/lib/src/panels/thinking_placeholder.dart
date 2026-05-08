import 'package:flutter/material.dart';

import '../panel_host.dart';
import '../thinking/thinking_panel.dart';

/// Mounts the Thinking tab in [ExplorationShell].
///
/// Renders [ThinkingPanel] when an active [ExplorationSession] is
/// available via [ExplorationPanelHost]; otherwise shows a hint.
class ThinkingPlaceholder extends StatelessWidget {
  const ThinkingPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final host = ExplorationPanelHost.of(context);
    final session = host.session;
    if (session == null) {
      return const Center(child: Text('No active session'));
    }
    return ThinkingPanel(session: session);
  }
}
