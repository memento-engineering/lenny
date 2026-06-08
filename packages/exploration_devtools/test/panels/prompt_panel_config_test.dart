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

  test('toJson round-trips through fromJson', () {
    final cfg = PromptPanelConfig(
      goal: 'test goal',
      modelId: 'ignored',
      maxTurns: 25,
      wallClockBudget: const Duration(minutes: 10),
      enabledPluginNamespaces: {'router', 'dio'},
    );
    final json = cfg.toJson();
    expect(json.containsKey('modelId'), isFalse);
    expect(json['goal'], 'test goal');
    expect(json['maxTurns'], 25);
    expect(json['wallClockBudgetMinutes'], 10);
    final restored = PromptPanelConfig.fromJson(json);
    expect(restored.goal, 'test goal');
    expect(restored.maxTurns, 25);
    expect(restored.wallClockBudget, const Duration(minutes: 10));
    expect(restored.enabledPluginNamespaces, {'router', 'dio'});
  });

  test('fromJson uses defaults for missing fields', () {
    final cfg = PromptPanelConfig.fromJson(const <String, dynamic>{});
    expect(cfg.goal, '');
    expect(cfg.maxTurns, 50);
    expect(cfg.wallClockBudget, const Duration(minutes: 15));
    expect(cfg.enabledPluginNamespaces, isEmpty);
  });

  test('toJson output contains no secret fields', () {
    final cfg = PromptPanelConfig(
      goal: 'g',
      modelId: 'secret-model',
      maxTurns: 50,
      wallClockBudget: const Duration(minutes: 15),
      enabledPluginNamespaces: const {},
    );
    final json = cfg.toJson();
    expect(json.containsKey('apiKey'), isFalse);
    expect(json.containsKey('bearerToken'), isFalse);
    expect(json.containsKey('password'), isFalse);
    expect(json.containsKey('modelId'), isFalse);
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
