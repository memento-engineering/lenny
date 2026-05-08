import 'package:exploration_devtools/src/panels/prompt_panel_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PromptPanelConfig equality is value-based', () {
    final a = PromptPanelConfig(
      goal: 'log in',
      modelId: 'mlx',
      maxTurns: 25,
      wallClockBudget: const Duration(minutes: 5),
      enabledPluginNamespaces: {'router', 'dio'},
    );
    final b = PromptPanelConfig(
      goal: 'log in',
      modelId: 'mlx',
      maxTurns: 25,
      wallClockBudget: const Duration(minutes: 5),
      enabledPluginNamespaces: {'dio', 'router'},
    );

    expect(a, equals(b));
    expect(a.hashCode, b.hashCode);
  });

  test('toExplorationConfig propagates budgets', () {
    final cfg = PromptPanelConfig(
      goal: 'log in',
      modelId: 'mlx',
      maxTurns: 25,
      wallClockBudget: const Duration(minutes: 5),
      enabledPluginNamespaces: const {},
    );

    final ec = cfg.toExplorationConfig();
    expect(ec.maxTurns, 25);
    expect(ec.sessionBudget, const Duration(minutes: 5));
  });
}
