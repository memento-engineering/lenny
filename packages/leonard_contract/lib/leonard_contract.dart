/// Pure-Dart extension contract for Leonard (PRD §7).
///
/// The Flutter-free surface that any host implements: value types, the
/// extension/tool contract, the perception bridge, and the registry. A
/// Flutter host (`leonard_flutter`) and a non-Flutter VM-service host
/// (`leonard_host`) both build on these identical types.
///
/// EXPERIMENTAL — see the versioning posture on `LeonardExtension`.
library;

export 'src/dispatch.dart' show decodeServiceExtensionParams, dispatchToolToEnvelope;
export 'src/extension.dart';
export 'src/extension_context.dart';
export 'src/perception_anchor.dart';
export 'src/perception_extension.dart';
export 'src/registry.dart' show ExtensionRegistry;
export 'src/types.dart';
