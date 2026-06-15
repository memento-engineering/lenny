import 'package:leonard_agent/leonard_agent.dart' show LeonardConfig;

/// Identifier + display label for a model surfaced in the prompt panel's
/// model dropdown. The widget is fed a list of these from the host so it
/// stays free of hardcoded model ids (PRD §6.3 / cx6.22 AC).
class ModelDescriptor {
  const ModelDescriptor({required this.id, required this.label});

  final String id;
  final String label;

  @override
  bool operator ==(Object other) => other is ModelDescriptor && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Immutable value snapshot of the prompt-panel form that is handed to
/// [LeonardSession] when the user presses Start. Implemented as a
/// value class so cx6.31 (mid-turn interrupt) can extend the wire shape
/// without restructuring the widget contract.
class PromptPanelConfig {
  const PromptPanelConfig({
    required this.goal,
    required this.modelId,
    required this.maxTurns,
    required this.wallClockBudget,
    required this.enabledExtensionNamespaces,
  });

  final String goal;
  final String modelId;
  final int maxTurns;
  final Duration wallClockBudget;
  final Set<String> enabledExtensionNamespaces;

  /// Project the turn / wall-clock budgets onto an [LeonardConfig].
  LeonardConfig toLeonardConfig() =>
      LeonardConfig(maxTurns: maxTurns, sessionBudget: wallClockBudget);

  /// Serializes form-level fields. [modelId] is intentionally absent —
  /// model selection is owned by the provider-config layer (lenny-0wd).
  Map<String, dynamic> toJson() => <String, dynamic>{
    'goal': goal,
    'maxTurns': maxTurns,
    'wallClockBudgetMinutes': wallClockBudget.inMinutes,
    'enabledExtensionNamespaces': enabledExtensionNamespaces.toList(),
  };

  factory PromptPanelConfig.fromJson(Map<String, dynamic> json) =>
      PromptPanelConfig(
        goal: (json['goal'] as String?) ?? '',
        modelId: '', // not persisted; resolved from model dropdown at mount
        maxTurns: (json['maxTurns'] as int?) ?? 50,
        wallClockBudget: Duration(
          minutes: (json['wallClockBudgetMinutes'] as int?) ?? 15,
        ),
        enabledExtensionNamespaces: Set<String>.from(
          (json['enabledExtensionNamespaces'] as List<dynamic>?) ??
              const <dynamic>[],
        ),
      );

  @override
  bool operator ==(Object other) =>
      other is PromptPanelConfig &&
      other.goal == goal &&
      other.modelId == modelId &&
      other.maxTurns == maxTurns &&
      other.wallClockBudget == wallClockBudget &&
      other.enabledExtensionNamespaces.length ==
          enabledExtensionNamespaces.length &&
      other.enabledExtensionNamespaces.containsAll(enabledExtensionNamespaces);

  @override
  int get hashCode => Object.hash(
    goal,
    modelId,
    maxTurns,
    wallClockBudget,
    Object.hashAllUnordered(enabledExtensionNamespaces),
  );
}
