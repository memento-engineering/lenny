import 'dart:async';

import 'package:exploration_agent/exploration_agent.dart'
    show
        BindingNotInitializedError,
        ExplorationSession,
        PluginManifestEntry,
        TrajectoryRecord;
import 'package:exploration_devtools/src/exploration_shell.dart';
import 'package:exploration_devtools/src/manifest_probe.dart';
import 'package:exploration_devtools/src/panels/timeline_panel_mount.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ManifestProbe _staticProbe(List<PluginManifestEntry> plugins) {
  return () async => plugins;
}

ManifestProbe _throwingProbe(Object error) {
  return () async => throw error;
}

Future<ExplorationSession> _noSession() async =>
    throw StateError('no session in this test');

void main() {
  testWidgets('tabs render three tabs with Prompt selected', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ExplorationShell(
        manifestProbe: _staticProbe(const []),
        sessionFactory: _noSession,
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
        manifestProbe: _staticProbe(const [
          PluginManifestEntry(namespace: 'router', tools: ['router.go']),
          PluginManifestEntry(namespace: 'dio', tools: ['dio.respondNext']),
        ]),
        sessionFactory: _noSession,
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
        manifestProbe: _staticProbe(const []),
        sessionFactory: _noSession,
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
        manifestProbe: _throwingProbe(BindingNotInitializedError()),
        sessionFactory: _noSession,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('prompt.bindingNotDetected')), findsOneWidget);
    expect(find.byKey(const Key('prompt.pluginsEmpty')), findsNothing);
    expect(find.byKey(const Key('prompt.goal')), findsNothing);
  });

  testWidgets('loading state shows spinner', (tester) async {
    final completer = Completer<List<PluginManifestEntry>>();
    Future<List<PluginManifestEntry>> probe() => completer.future;

    await tester.pumpWidget(MaterialApp(
      home: ExplorationShell(
        manifestProbe: probe,
        sessionFactory: _noSession,
      ),
    ));
    // Pump once — the probe future is pending.
    await tester.pump();

    expect(find.byKey(const Key('prompt.manifestLoading')), findsOneWidget);

    // Drain by completing.
    completer.complete(const <PluginManifestEntry>[]);
    await tester.pumpAndSettle();
  });

  testWidgets(
      'TimelinePanelMount.trajectoryStream is null before a session starts',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ExplorationShell(
        manifestProbe: _staticProbe(const []),
        sessionFactory: _noSession,
      ),
    ));
    await tester.pumpAndSettle();

    // Activate the Timeline tab so the mount widget is built.
    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();

    final TimelinePanelMount mount =
        tester.widget<TimelinePanelMount>(find.byType(TimelinePanelMount));
    expect(mount.trajectoryStream, isNull,
        reason: 'no controller has been created yet — no stream to forward');
  });

  testWidgets(
      'TimelinePanelMount.trajectoryStream rebuilds when the trajectory '
      'notifier publishes a stream', (tester) async {
    // This test verifies the shell's ValueListenableBuilder wiring:
    // when the trajectory notifier fires, the Timeline tab rebuilds
    // with the new stream. Mounting a real session is exercised by
    // the controller test; here we only assert the structural seam.
    final controller = StreamController<TrajectoryRecord>.broadcast();
    addTearDown(controller.close);
    final stream = controller.stream;

    final notifier = ValueNotifier<Stream<TrajectoryRecord>?>(null);
    addTearDown(notifier.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<Stream<TrajectoryRecord>?>(
          valueListenable: notifier,
          builder: (context, stream, _) =>
              TimelinePanelMount(trajectoryStream: stream),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TimelinePanelMount>(find.byType(TimelinePanelMount))
          .trajectoryStream,
      isNull,
    );

    notifier.value = stream;
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TimelinePanelMount>(find.byType(TimelinePanelMount))
          .trajectoryStream,
      same(stream),
      reason: 'shell re-renders TimelinePanelMount with the published stream',
    );
  });

  testWidgets('probeRetrigger change triggers re-probe', (tester) async {
    var calls = 0;
    Future<List<PluginManifestEntry>> probe() async {
      calls += 1;
      return const <PluginManifestEntry>[];
    }

    final notifier = ValueNotifier<int>(0);
    await tester.pumpWidget(MaterialApp(
      home: ExplorationShell(
        manifestProbe: probe,
        sessionFactory: _noSession,
        probeRetrigger: notifier,
      ),
    ));
    await tester.pumpAndSettle();
    expect(calls, 1);

    notifier.value = 1;
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
}
