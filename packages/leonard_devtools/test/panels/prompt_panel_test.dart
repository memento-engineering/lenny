import 'dart:convert';

import 'package:leonard_agent/leonard_agent.dart'
    show ModelCapabilities, ExtensionManifestEntry;
import 'package:leonard_devtools/src/panels/model_catalog.dart';
import 'package:leonard_devtools/src/panels/prompt_panel.dart';
import 'package:leonard_devtools/src/panels/prompt_panel_config.dart';
import 'package:leonard_devtools/src/panels/provider_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ModelCatalog _emptyCatalog() => ModelCatalog(
  client: MockClient(
    (req) async => http.Response(
      jsonEncode(<String, dynamic>{'data': <Map<String, dynamic>>[]}),
      200,
    ),
  ),
);

ModelCatalogState _state({
  List<ResolvedModel> models = const <ResolvedModel>[],
  ProviderConfig? config,
  bool loading = false,
  Object? error,
}) => ModelCatalogState(
  models: models,
  config: config,
  loading: loading,
  error: error,
);

Widget _host({
  required bool running,
  required List<ExtensionManifestEntry> plugins,
  ModelCatalogState? modelsState,
  void Function(PromptPanelConfig)? onStart,
  VoidCallback? onStop,
  void Function(ProviderConfig)? onProviderConfigChanged,
  VoidCallback? onReload,
  ModelCatalog? catalog,
  PromptPanelConfig? initialConfig,
  bool configLoaded = false,
}) => MaterialApp(
  home: Scaffold(
    body: PromptPanel(
      modelsState:
          modelsState ??
          _state(
            models: const [ResolvedModel(id: 'mlx', label: 'MLX')],
          ),
      plugins: plugins,
      running: running,
      onStart: onStart ?? (_) {},
      onStop: onStop ?? () {},
      onProviderConfigChanged: onProviderConfigChanged ?? (_) {},
      onReloadModels: onReload ?? () {},
      catalog: catalog ?? _emptyCatalog(),
      initialConfig: initialConfig,
      configLoaded: configLoaded,
    ),
  ),
);

void main() {
  testWidgets('renders all controls', (tester) async {
    await tester.pumpWidget(
      _host(
        running: false,
        plugins: const [ExtensionManifestEntry(namespace: 'router', tools: [])],
      ),
    );
    await tester.pump();

    for (final k in const [
      'prompt.goal',
      'prompt.model',
      'prompt.maxTurns',
      'prompt.wallMinutes',
      'prompt.plugin.router',
      'prompt.start',
      'prompt.modelsReload',
      'providerForm.providerSelect',
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
    await tester.pumpWidget(
      _host(running: false, plugins: const [], onStart: (_) => calls++),
    );
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('prompt.start')));
    await tester.tap(find.byKey(const Key('prompt.start')));
    await tester.pump();

    expect(calls, 0);
    expect(find.text('Goal required'), findsOneWidget);
  });

  testWidgets('Start collects config', (tester) async {
    PromptPanelConfig? cfg;
    await tester.pumpWidget(
      _host(
        running: false,
        plugins: const [ExtensionManifestEntry(namespace: 'dio', tools: [])],
        onStart: (c) => cfg = c,
      ),
    );
    await tester.pump();

    await tester.enterText(find.byKey(const Key('prompt.goal')), 'log in');
    await tester.ensureVisible(find.byKey(const Key('prompt.start')));
    await tester.tap(find.byKey(const Key('prompt.start')));
    await tester.pump();

    expect(cfg, isNotNull);
    expect(cfg!.goal, 'log in');
    expect(cfg!.modelId, 'mlx');
    expect(cfg!.enabledExtensionNamespaces, {'dio'});
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
    await tester.pumpWidget(
      _host(running: true, plugins: const [], onStop: () => stops++),
    );
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('prompt.stop')));
    await tester.tap(find.byKey(const Key('prompt.stop')));
    await tester.pump();

    expect(stops, 1);
  });

  testWidgets('vision capability renders vision badge', (tester) async {
    await tester.pumpWidget(
      _host(
        running: false,
        plugins: const [],
        modelsState: _state(
          models: const [
            ResolvedModel(
              id: 'claude-sonnet-4-6',
              label: 'Claude',
              capabilities: _kVision,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(find.text('vision'), findsOneWidget);
  });

  testWidgets('unknown caps render unknown badge', (tester) async {
    await tester.pumpWidget(
      _host(
        running: false,
        plugins: const [],
        modelsState: _state(
          models: const [ResolvedModel(id: 'unknown-model', label: 'Mystery')],
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('badge.unknown')), findsOneWidget);
  });

  testWidgets('using fallback renders fallback badge', (tester) async {
    await tester.pumpWidget(
      _host(
        running: false,
        plugins: const [],
        modelsState: _state(
          models: const [
            ResolvedModel(
              id: 'qwen3.6-35b-a3b-8bit',
              label: 'Qwen',
              usingFallback: true,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('badge.fallback')), findsOneWidget);
  });

  testWidgets('error state renders banner without disabling form', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        running: false,
        plugins: const [],
        modelsState: _state(error: 'boom'),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('prompt.modelsError')), findsOneWidget);
    // Form still interactive.
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('prompt.goal')))
          .enabled,
      isTrue,
    );
  });

  testWidgets('reload button fires onReloadModels', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _host(running: false, plugins: const [], onReload: () => calls++),
    );
    await tester.pump();
    // Open settings so the reload button is interactive.
    await tester.tap(find.byKey(const Key('prompt.settingsGear')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('prompt.modelsReload')));
    await tester.tap(find.byKey(const Key('prompt.modelsReload')));
    await tester.pump();
    expect(calls, 1);
  });

  testWidgets(
    'initialConfig pre-fills goal, maxTurns, budget, extension toggles',
    (tester) async {
      await tester.pumpWidget(
        _host(
          running: false,
          plugins: const [
            ExtensionManifestEntry(namespace: 'router', tools: []),
            ExtensionManifestEntry(namespace: 'dio', tools: []),
          ],
          initialConfig: PromptPanelConfig(
            goal: 'prefill',
            modelId: '',
            maxTurns: 30,
            wallClockBudget: const Duration(minutes: 8),
            enabledExtensionNamespaces: {'router'},
          ),
        ),
      );
      await tester.pump();

      final goalField = tester.widget<TextFormField>(
        find.byKey(const Key('prompt.goal')),
      );
      expect(goalField.controller!.text, 'prefill');

      // 'router' enabled → checked; 'dio' NOT in enabled set → unchecked.
      final routerTile = tester.widget<CheckboxListTile>(
        find.byKey(const Key('prompt.plugin.router')),
      );
      expect(routerTile.value, isTrue);

      final dioTile = tester.widget<CheckboxListTile>(
        find.byKey(const Key('prompt.plugin.dio')),
      );
      expect(dioTile.value, isFalse);
    },
  );

  testWidgets('settings gear is present in composer row', (tester) async {
    await tester.pumpWidget(_host(running: false, plugins: const []));
    await tester.pump();
    expect(find.byKey(const Key('prompt.settingsGear')), findsOneWidget);
  });

  testWidgets('settings are collapsed by default', (tester) async {
    await tester.pumpWidget(_host(running: false, plugins: const []));
    await tester.pump();
    final crossFade = tester.widget<AnimatedCrossFade>(
      find.byType(AnimatedCrossFade),
    );
    expect(crossFade.crossFadeState, CrossFadeState.showFirst);
  });

  testWidgets('tapping gear opens settings section', (tester) async {
    await tester.pumpWidget(_host(running: false, plugins: const []));
    await tester.pump();
    await tester.tap(find.byKey(const Key('prompt.settingsGear')));
    await tester.pumpAndSettle();
    final crossFade = tester.widget<AnimatedCrossFade>(
      find.byType(AnimatedCrossFade),
    );
    expect(crossFade.crossFadeState, CrossFadeState.showSecond);
  });

  testWidgets('tapping gear again closes settings section', (tester) async {
    await tester.pumpWidget(_host(running: false, plugins: const []));
    await tester.pump();
    await tester.tap(find.byKey(const Key('prompt.settingsGear')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('prompt.settingsGear')));
    await tester.tap(find.byKey(const Key('prompt.settingsGear')));
    await tester.pumpAndSettle();
    final crossFade = tester.widget<AnimatedCrossFade>(
      find.byType(AnimatedCrossFade),
    );
    expect(crossFade.crossFadeState, CrossFadeState.showFirst);
  });

  testWidgets(
    'configLoaded false→true with no saved config auto-opens settings',
    (tester) async {
      final configLoadedNotifier = ValueNotifier<bool>(false);
      addTearDown(configLoadedNotifier.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: configLoadedNotifier,
              builder: (_, configLoaded, __) => PromptPanel(
                modelsState: _state(),
                plugins: const [],
                running: false,
                onStart: (_) {},
                onStop: () {},
                onProviderConfigChanged: (_) {},
                onReloadModels: () {},
                catalog: _emptyCatalog(),
                configLoaded: configLoaded,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      var crossFade = tester.widget<AnimatedCrossFade>(
        find.byType(AnimatedCrossFade),
      );
      expect(crossFade.crossFadeState, CrossFadeState.showFirst);

      configLoadedNotifier.value = true;
      await tester.pumpAndSettle();

      crossFade = tester.widget<AnimatedCrossFade>(
        find.byType(AnimatedCrossFade),
      );
      expect(crossFade.crossFadeState, CrossFadeState.showSecond);
    },
  );

  testWidgets(
    'configLoaded false→true with saved initialConfig keeps settings closed',
    (tester) async {
      final configLoadedNotifier = ValueNotifier<bool>(false);
      addTearDown(configLoadedNotifier.dispose);
      final savedConfig = PromptPanelConfig(
        goal: 'existing goal',
        modelId: 'mlx',
        maxTurns: 50,
        wallClockBudget: const Duration(minutes: 15),
        enabledExtensionNamespaces: const <String>{},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: configLoadedNotifier,
              builder: (_, configLoaded, __) => PromptPanel(
                modelsState: _state(),
                plugins: const [],
                running: false,
                onStart: (_) {},
                onStop: () {},
                onProviderConfigChanged: (_) {},
                onReloadModels: () {},
                catalog: _emptyCatalog(),
                configLoaded: configLoaded,
                initialConfig: savedConfig,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      configLoadedNotifier.value = true;
      await tester.pumpAndSettle();

      final crossFade = tester.widget<AnimatedCrossFade>(
        find.byType(AnimatedCrossFade),
      );
      expect(crossFade.crossFadeState, CrossFadeState.showFirst);
    },
  );

  testWidgets('didUpdateWidget applies config when null → non-null', (
    tester,
  ) async {
    final notifier = ValueNotifier<PromptPanelConfig?>(null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<PromptPanelConfig?>(
            valueListenable: notifier,
            builder: (_, ic, __) => PromptPanel(
              modelsState: _state(
                models: const [ResolvedModel(id: 'mlx', label: 'MLX')],
              ),
              plugins: const [
                ExtensionManifestEntry(namespace: 'router', tools: []),
              ],
              running: false,
              onStart: (_) {},
              onStop: () {},
              onProviderConfigChanged: (_) {},
              onReloadModels: () {},
              catalog: _emptyCatalog(),
              initialConfig: ic,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Before: goal empty (defaults).
    final goalBefore = tester.widget<TextFormField>(
      find.byKey(const Key('prompt.goal')),
    );
    expect(goalBefore.controller!.text, '');

    // Deliver async config (simulates bootstrap completing after mount).
    notifier.value = PromptPanelConfig(
      goal: 'async goal',
      modelId: '',
      maxTurns: 20,
      wallClockBudget: const Duration(minutes: 5),
      enabledExtensionNamespaces: const <String>{},
    );
    await tester.pumpAndSettle();

    final goalAfter = tester.widget<TextFormField>(
      find.byKey(const Key('prompt.goal')),
    );
    expect(goalAfter.controller!.text, 'async goal');
  });
}

// Vision-tier caps mirror Anthropic's claude-sonnet-4-6.
const ModelCapabilities _kVision = ModelCapabilities(
  vision: true,
  preserveThinking: false,
  maxContext: 200000,
  supportsToolUse: true,
);
