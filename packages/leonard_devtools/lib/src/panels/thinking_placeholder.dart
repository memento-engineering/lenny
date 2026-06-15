import 'package:leonard_agent/leonard_agent.dart' show LeonardSession;
import 'package:flutter/material.dart';

import '../panel_host.dart';
import '../thinking/thinking_panel.dart';

/// Mounts the Thinking tab in [LeonardShell].
///
/// Renders [ThinkingPanel] when an active [LeonardSession] is
/// available via [LeonardPanelHost]; otherwise shows a hint.
class ThinkingPlaceholder extends StatelessWidget {
  const ThinkingPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final host = LeonardPanelHost.of(context);
    return ValueListenableBuilder<LeonardSession?>(
      valueListenable: host.sessionListenable,
      builder: (context, session, _) {
        if (session == null) {
          return const Center(child: Text('No active session'));
        }
        return ThinkingPanel(session: session);
      },
    );
  }
}
