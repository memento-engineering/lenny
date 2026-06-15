/// CLI-side alias for the extension-tool projection helpers.
///
/// The actual implementation lives in `leonard_agent` (see
/// `package:leonard_agent/leonard_agent.dart`) so the CLI and
/// the DevTools panel share one code path when projecting a user's
/// requested extension namespaces against the binding's handshake
/// manifest into the `extensionTools` map handed to
/// `DefaultLoopHost.fromSession`.
library;

export 'package:leonard_agent/leonard_agent.dart'
    show buildExtensionTools, unknownExtensionNamespaces;
