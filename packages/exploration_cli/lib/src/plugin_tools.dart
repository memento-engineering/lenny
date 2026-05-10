/// CLI-side alias for the plugin-tool projection helpers.
///
/// The actual implementation lives in `exploration_agent` (see
/// `package:exploration_agent/exploration_agent.dart`) so the CLI and
/// the DevTools panel share one code path when projecting a user's
/// requested plugin namespaces against the binding's handshake
/// manifest into the `pluginTools` map handed to
/// `DefaultLoopHost.fromSession`.
library;

export 'package:exploration_agent/exploration_agent.dart'
    show buildPluginTools, unknownPluginNamespaces;
