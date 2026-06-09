import 'dart:async';

import 'package:exploration_agent/exploration_agent.dart'
    show BindingNotInitializedError, ExplorationSession, PluginManifestEntry;
import 'package:exploration_devtools/src/exploration_shell.dart';
import 'package:exploration_devtools/src/manifest_probe.dart';
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

  testWidgets('idle screen shows idle hint before session starts',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ExplorationShell(
        manifestProbe: _staticProbe(const []),
        sessionFactory: _noSession,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('transcript.idle')), findsOneWidget);
  });

  testWidgets('shows runStatus.idle chip before session starts', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ExplorationShell(
        manifestProbe: _staticProbe(const []),
        sessionFactory: _noSession,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('runStatus.idle')), findsOneWidget);
  });

  testWidgets('no tab bar in single-screen layout', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ExplorationShell(
        manifestProbe: _staticProbe(const []),
        sessionFactory: _noSession,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(TabBar), findsNothing);
  });

  testWidgets('goal field is visible in the composer', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ExplorationShell(
        manifestProbe: _staticProbe(const []),
        sessionFactory: _noSession,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('prompt.goal')), findsOneWidget);
  });

  testWidgets('no context meter before session starts', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ExplorationShell(
        manifestProbe: _staticProbe(const []),
        sessionFactory: _noSession,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('contextMeter.text')), findsNothing);
  });
}
