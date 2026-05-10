import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

import 'src/exploration_shell.dart';

void main() => runApp(const ExplorationDevToolsExtension());

/// Top-level extension widget. Wraps [ExplorationShell] in [DevToolsExtension]
/// so DevTools provides Material theming, the VM service, and DTD.
///
/// `serviceManager` is a top-level getter that throws until
/// `DevToolsExtension`'s State.initState has run. Any read at or above
/// `DevToolsExtension` in the widget tree fails on the first frame with
/// `Bad state: 'serviceManager' has not been initialized yet`. The
/// [Builder] below pushes the reads into a descendant build call that
/// runs only after `DevToolsExtension` has initialized — see
/// devtools_extensions's own README ("serviceManager getters … below
/// the DevToolsExtension widget in the widget tree").
class ExplorationDevToolsExtension extends StatelessWidget {
  const ExplorationDevToolsExtension({super.key});

  @override
  Widget build(BuildContext context) => DevToolsExtension(
        child: Builder(
          builder: (BuildContext context) => ExplorationShell(
            vmServiceUri: () => serviceManager.serviceUri,
            // Reconnects (e.g. hot-restart of the target app) flip
            // connectedState; the shell listens and re-probes the
            // manifest. Read inside the Builder so the access happens
            // after DevToolsExtension.initState — not in the parent's
            // build, where serviceManager throws.
            vmServiceUriListenable: serviceManager.connectedState,
          ),
        ),
      );
}
