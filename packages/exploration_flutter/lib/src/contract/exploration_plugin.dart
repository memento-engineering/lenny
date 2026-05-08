/// Marker base class. cx6.3 owns the full contract (tools, observe,
/// busyState, lifecycle, PluginContext) and extends this type
/// additively. cx6.2 only relies on [namespace].
abstract class ExplorationPlugin {
  const ExplorationPlugin();

  /// Namespace for this plugin's tools and VM service extensions.
  /// Must match `^[a-z][a-z0-9_]*$` (validated by cx6.3 registry).
  String get namespace;
}
