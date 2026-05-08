import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

import 'src/exploration_shell.dart';

void main() => runApp(const ExplorationDevToolsExtension());

/// Top-level extension widget. Wraps [ExplorationShell] in [DevToolsExtension]
/// so DevTools provides Material theming, the VM service, and DTD.
class ExplorationDevToolsExtension extends StatelessWidget {
  const ExplorationDevToolsExtension({super.key});

  @override
  Widget build(BuildContext context) => DevToolsExtension(
        child: ExplorationShell(vmServiceUri: () => serviceManager.serviceUri),
      );
}
