import 'package:exploration_agent/exploration_agent.dart' show ExplorationConfig;

/// Identifier + display label for a model surfaced in the prompt panel's
/// model dropdown. The widget is fed a list of these from the host so it
/// stays free of hardcoded model ids (PRD §6.3 / cx6.22 AC).
class ModelDescriptor {
  const ModelDescriptor({required this.id, required this.label});

  final String id;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is ModelDescriptor && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Immutable value snapshot of the prompt-panel form that is handed to
/// [ExplorationSession] when the user presses Start. Implemented as a
/// value class so cx6.31 (mid-turn interrupt) can extend the wire shape
/// without restructuring the widget contract.
class PromptPanelConfig {
  const PromptPanelConfig({
    required this.goal,
    required this.modelId,
    required this.maxTurns,
    required this.wallClockBudget,
    required this.enabledPluginNamespaces,
  });

  final String goal;
  final String modelId;
  final int maxTurns;
  final Duration wallClockBudget;
  final Set<String> enabledPluginNamespaces;

  /// Project the turn / wall-clock budgets onto an [ExplorationConfig].
  ExplorationConfig toExplorationConfig() => ExplorationConfig(
        maxTurns: maxTurns,
        sessionBudget: wallClockBudget,
      );

  @override
  bool operator ==(Object other) =>
      other is PromptPanelConfig &&
      other.goal == goal &&
      other.modelId == modelId &&
      other.maxTurns == maxTurns &&
      other.wallClockBudget == wallClockBudget &&
      other.enabledPluginNamespaces.length ==
          enabledPluginNamespaces.length &&
      other.enabledPluginNamespaces.containsAll(enabledPluginNamespaces);

  @override
  int get hashCode => Object.hash(
        goal,
        modelId,
        maxTurns,
        wallClockBudget,
        Object.hashAllUnordered(enabledPluginNamespaces),
      );
}
