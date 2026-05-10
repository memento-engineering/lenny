import 'dart:async';

import 'package:exploration_agent/exploration_agent.dart'
    show BindingNotInitializedError, PluginManifestEntry;
import 'package:exploration_devtools/src/exploration_shell.dart';
import 'package:exploration_devtools/src/manifest_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ManifestProbe _staticProbe(List<PluginManifestEntry> plugins) {
  return (Uri _) async => plugins;
}

ManifestProbe _throwingProbe(Object error) {
  return (Uri _) async => throw error;
}

void main() {
  testWidgets('tabs render three tabs with Prompt selected', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ExplorationShell(
        vmServiceUri: () => 'ws://localhost:9999/abc/',
        manifestProbe: _staticProbe(const []),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Prompt'), findsOneWidget);
    expect(find.text('Thinking'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    // The Prompt tab is selected by default — its real PromptPanel
    // (cx6.22) is mounted, so its goal field is visible.
    expect(find.byKey(const Key('prompt.goal')), findsOneWidget);
  });

  testWidgets('renders one toggle per plugin namespace from probe',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ExplorationShell(
        vmServiceUri: () => 'ws://localhost:9999/abc/',
        manifestProbe: _staticProbe(const [
          PluginManifestEntry(namespace: 'router', tools: ['router.go']),
          PluginManifestEntry(namespace: 'dio', tools: ['dio.respondNext']),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('prompt.plugin.router')), findsOneWidget);
    expect(find.byKey(const Key('prompt.plugin.dio')), findsOneWidget);
    expect(find.byKey(const Key('prompt.pluginsEmpty')), findsNothing);
  });

  testWidgets('empty plugin list renders empty-state hint', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ExplorationShell(
        vmServiceUri: () => 'ws://localhost:9999/abc/',
        manifestProbe: _staticProbe(const []),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('prompt.pluginsEmpty')), findsOneWidget);
    expect(find.byKey(const Key('prompt.bindingNotDetected')), findsNothing);
  });

  testWidgets('binding missing renders prompt.bindingNotDetected',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ExplorationShell(
        vmServiceUri: () => 'ws://localhost:9999/abc/',
        manifestProbe: _throwingProbe(BindingNotInitializedError()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('prompt.bindingNotDetected')), findsOneWidget);
    expect(find.byKey(const Key('prompt.pluginsEmpty')), findsNothing);
    expect(find.byKey(const Key('prompt.goal')), findsNothing);
  });

  testWidgets('loading state shows spinner', (tester) async {
    final completer = Completer<List<PluginManifestEntry>>();
    Future<List<PluginManifestEntry>> probe(Uri _) => completer.future;

    await tester.pumpWidget(MaterialApp(
      home: ExplorationShell(
        vmServiceUri: () => 'ws://localhost:9999/abc/',
        manifestProbe: probe,
      ),
    ));
    // Pump once — the probe future is pending.
    await tester.pump();

    expect(find.byKey(const Key('prompt.manifestLoading')), findsOneWidget);

    // Drain by completing.
    completer.complete(const <PluginManifestEntry>[]);
    await tester.pumpAndSettle();
  });

  testWidgets('vmServiceUriListenable change triggers re-probe',
      (tester) async {
    var calls = 0;
    Future<List<PluginManifestEntry>> probe(Uri _) async {
      calls += 1;
      return const <PluginManifestEntry>[];
    }

    final notifier = ValueNotifier<int>(0);
    await tester.pumpWidget(MaterialApp(
      home: ExplorationShell(
        vmServiceUri: () => 'ws://localhost:9999/abc/',
        manifestProbe: probe,
        vmServiceUriListenable: notifier,
      ),
    ));
    await tester.pumpAndSettle();
    expect(calls, 1);

    notifier.value = 1;
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
}
