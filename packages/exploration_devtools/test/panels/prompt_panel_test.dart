import 'package:exploration_agent/exploration_agent.dart'
    show PluginManifestEntry;
import 'package:exploration_devtools/src/panels/prompt_panel.dart';
import 'package:exploration_devtools/src/panels/prompt_panel_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  required bool running,
  required List<PluginManifestEntry> plugins,
  void Function(PromptPanelConfig)? onStart,
  VoidCallback? onStop,
}) =>
    MaterialApp(
      home: Scaffold(
        body: PromptPanel(
          availableModels: const [
            ModelDescriptor(id: 'mlx', label: 'MLX'),
          ],
          plugins: plugins,
          running: running,
          onStart: onStart ?? (_) {},
          onStop: onStop ?? () {},
        ),
      ),
    );

void main() {
  testWidgets('renders all controls', (tester) async {
    await tester.pumpWidget(_host(
      running: false,
      plugins: const [PluginManifestEntry(namespace: 'router', tools: [])],
    ));
    await tester.pump();

    for (final k in const [
      'prompt.goal',
      'prompt.model',
      'prompt.maxTurns',
      'prompt.wallMinutes',
      'prompt.plugin.router',
      'prompt.start',
    ]) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }
  });

  testWidgets('empty plugin list shows guide hint', (tester) async {
    await tester.pumpWidget(_host(running: false, plugins: const []));
    await tester.pump();

    expect(find.byKey(const Key('prompt.pluginsEmpty')), findsOneWidget);
  });

  testWidgets('Start with empty goal does not fire onStart', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_host(
      running: false,
      plugins: const [],
      onStart: (_) => calls++,
    ));
    await tester.pump();

    await tester.tap(find.byKey(const Key('prompt.start')));
    await tester.pump();

    expect(calls, 0);
    expect(find.text('Goal required'), findsOneWidget);
  });

  testWidgets('Start collects config', (tester) async {
    PromptPanelConfig? cfg;
    await tester.pumpWidget(_host(
      running: false,
      plugins: const [PluginManifestEntry(namespace: 'dio', tools: [])],
      onStart: (c) => cfg = c,
    ));
    await tester.pump();

    await tester.enterText(find.byKey(const Key('prompt.goal')), 'log in');
    await tester.tap(find.byKey(const Key('prompt.start')));
    await tester.pump();

    expect(cfg, isNotNull);
    expect(cfg!.goal, 'log in');
    expect(cfg!.modelId, 'mlx');
    expect(cfg!.enabledPluginNamespaces, {'dio'});
  });

  testWidgets('running disables inputs and shows Stop', (tester) async {
    await tester.pumpWidget(_host(running: true, plugins: const []));
    await tester.pump();

    expect(find.byKey(const Key('prompt.stop')), findsOneWidget);
    expect(find.byKey(const Key('prompt.start')), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('prompt.goal')))
          .enabled,
      isFalse,
    );
  });

  testWidgets('Stop fires onStop exactly once', (tester) async {
    var stops = 0;
    await tester.pumpWidget(_host(
      running: true,
      plugins: const [],
      onStop: () => stops++,
    ));
    await tester.pump();

    await tester.tap(find.byKey(const Key('prompt.stop')));
    await tester.pump();

    expect(stops, 1);
  });
}
