import 'dart:async';

import 'package:leonard_agent/leonard_agent.dart'
    show
        BindingNotInitializedError,
        ExtensionManifestEntry,
        LeonardSession,
        TrajectoryRecord,
        TurnRecord;
import 'package:leonard_devtools/src/diagnostics/diagnostics_panel.dart';
import 'package:leonard_devtools/src/diagnostics/diagnostics_snapshot.dart';
import 'package:leonard_devtools/src/leonard_shell.dart';
import 'package:leonard_devtools/src/manifest_probe.dart';
import 'package:leonard_devtools/src/panels/timeline_panel_mount.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_foundation/genesis_foundation.dart';

ManifestProbe _staticProbe(List<ExtensionManifestEntry> extensions) {
  return () async => extensions;
}

ManifestProbe _throwingProbe(Object error) {
  return () async => throw error;
}

Future<LeonardSession> _noSession() async =>
    throw StateError('no session in this test');

Future<TreeSnapshot> _noDiagnostics() async =>
    throw StateError('no diagnostics in this test');

const TurnRecord _liveTurn = TurnRecord(
  index: 0,
  observation: <String, dynamic>{
    'core': <String, dynamic>{},
    'extensions': <String, dynamic>{},
  },
  stability: <String, dynamic>{},
  proposedAction: <String, dynamic>{'tool': 'core.done'},
  validation: <String, dynamic>{'ok': true},
  executedAction: <String, dynamic>{
    'tool': 'core.done',
    'args': <String, dynamic>{},
  },
  diff: <String, dynamic>{},
  modelMetadata: <String, dynamic>{},
);

void main() {
  testWidgets('binding missing renders prompt.bindingNotDetected', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LeonardShell(
          manifestProbe: _throwingProbe(BindingNotInitializedError()),
          sessionFactory: _noSession,
          diagnosticsSnapshotLoader: _noDiagnostics,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('prompt.bindingNotDetected')), findsOneWidget);
    expect(find.byKey(const Key('prompt.goal')), findsNothing);
  });

  testWidgets('loading state shows spinner', (tester) async {
    final completer = Completer<List<ExtensionManifestEntry>>();
    Future<List<ExtensionManifestEntry>> probe() => completer.future;

    await tester.pumpWidget(
      MaterialApp(
        home: LeonardShell(
          manifestProbe: probe,
          sessionFactory: _noSession,
          diagnosticsSnapshotLoader: _noDiagnostics,
        ),
      ),
    );
    // Pump once — the probe future is pending.
    await tester.pump();

    expect(find.byKey(const Key('prompt.manifestLoading')), findsOneWidget);

    // Drain by completing.
    completer.complete(const <ExtensionManifestEntry>[]);
    await tester.pumpAndSettle();
  });

  testWidgets('probeRetrigger change triggers re-probe', (tester) async {
    var calls = 0;
    Future<List<ExtensionManifestEntry>> probe() async {
      calls += 1;
      return const <ExtensionManifestEntry>[];
    }

    final notifier = ValueNotifier<int>(0);
    await tester.pumpWidget(
      MaterialApp(
        home: LeonardShell(
          manifestProbe: probe,
          sessionFactory: _noSession,
          diagnosticsSnapshotLoader: _noDiagnostics,
          probeRetrigger: notifier,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);

    notifier.value = 1;
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('idle screen shows idle hint before session starts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LeonardShell(
          manifestProbe: _staticProbe(const []),
          sessionFactory: _noSession,
          diagnosticsSnapshotLoader: _noDiagnostics,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('transcript.idle')), findsOneWidget);
  });

  testWidgets('shows runStatus.idle chip before session starts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LeonardShell(
          manifestProbe: _staticProbe(const []),
          sessionFactory: _noSession,
          diagnosticsSnapshotLoader: _noDiagnostics,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('runStatus.idle')), findsOneWidget);
  });

  testWidgets('offers conversation, timeline, and diagnostics modes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LeonardShell(
          manifestProbe: _staticProbe(const []),
          sessionFactory: _noSession,
          diagnosticsSnapshotLoader: _noDiagnostics,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('Conversation'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Diagnostics'), findsOneWidget);
    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();
    expect(find.byType(TimelinePanelMount), findsOneWidget);
  });

  testWidgets('TimelinePanelMount rebinds to a post-Start stream', (
    tester,
  ) async {
    final ValueNotifier<Stream<TrajectoryRecord>?> trajectory =
        ValueNotifier<Stream<TrajectoryRecord>?>(null);
    final StreamController<TrajectoryRecord> controller =
        StreamController<TrajectoryRecord>.broadcast();
    addTearDown(trajectory.dispose);
    addTearDown(controller.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<Stream<TrajectoryRecord>?>(
            valueListenable: trajectory,
            builder: (context, stream, _) =>
                TimelinePanelMount(trajectoryStream: stream),
          ),
        ),
      ),
    );
    await tester.pump();

    trajectory.value = controller.stream;
    await tester.pump();
    controller.add(_liveTurn);
    await tester.pump();
    await tester.pump();

    expect(find.text('#0 core.done()'), findsOneWidget);
  });

  testWidgets('goal field is visible in the composer', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LeonardShell(
          manifestProbe: _staticProbe(const []),
          sessionFactory: _noSession,
          diagnosticsSnapshotLoader: _noDiagnostics,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('prompt.goal')), findsOneWidget);
  });

  testWidgets('no context meter before session starts', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LeonardShell(
          manifestProbe: _staticProbe(const []),
          sessionFactory: _noSession,
          diagnosticsSnapshotLoader: _noDiagnostics,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('contextMeter.text')), findsNothing);
  });

  group('Diagnostics mode', () {
    TreeSnapshot snap(String id) => TreeSnapshot(
      contractVersion: 1,
      projectedAt: DateTime.utc(2026, 8, 1),
      root: TreeNode(
        seedType: 'Root',
        id: id,
        properties: const <DiagnosticsProperty>[],
        children: const <TreeNode>[],
      ),
    );

    Widget shell(DiagnosticsSnapshotLoader loader) => MaterialApp(
      home: LeonardShell(
        manifestProbe: _staticProbe(const []),
        sessionFactory: _noSession,
        diagnosticsSnapshotLoader: loader,
      ),
    );

    testWidgets(
      'opening the tab performs exactly one initial refresh: '
      'loading then loaded',
      (tester) async {
        final List<Completer<TreeSnapshot>> completers =
            <Completer<TreeSnapshot>>[];
        Future<TreeSnapshot> loader() {
          final Completer<TreeSnapshot> c = Completer<TreeSnapshot>();
          completers.add(c);
          return c.future;
        }

        await tester.pumpWidget(shell(loader));
        await tester.pumpAndSettle();
        // Conversation is the initial tab — no diagnostics load yet.
        expect(completers, isEmpty);

        await tester.tap(find.text('Diagnostics'));
        // Bounded pumps: the loading spinner animates forever, so
        // pumpAndSettle would never settle.
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(completers, hasLength(1));
        expect(find.byKey(const Key('diagnostics.loading')), findsOneWidget);

        completers.single.complete(snap('root'));
        await tester.pumpAndSettle();
        expect(completers, hasLength(1), reason: 'exactly one initial refresh');
        expect(find.byKey(const Key('diagnostics.tree')), findsOneWidget);
        expect(find.byKey(const Key('diagnostics.loading')), findsNothing);
      },
    );

    testWidgets('manual refresh surfaces the error, then recovers', (
      tester,
    ) async {
      final List<Completer<TreeSnapshot>> completers =
          <Completer<TreeSnapshot>>[];
      Future<TreeSnapshot> loader() {
        final Completer<TreeSnapshot> c = Completer<TreeSnapshot>();
        completers.add(c);
        return c.future;
      }

      await tester.pumpWidget(shell(loader));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diagnostics'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      completers.single.complete(snap('root'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('diagnostics.tree')), findsOneWidget);

      // Manual refresh → failure state.
      await tester.tap(find.byKey(const Key('diagnostics.refresh')));
      await tester.pump();
      expect(completers, hasLength(2));
      expect(find.byKey(const Key('diagnostics.loading')), findsOneWidget);
      completers[1].completeError(StateError('diagnostics unavailable'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('diagnostics.error')), findsOneWidget);
      expect(find.textContaining('diagnostics unavailable'), findsOneWidget);

      // Manual refresh → success again.
      await tester.tap(find.byKey(const Key('diagnostics.refresh')));
      await tester.pump();
      expect(completers, hasLength(3));
      completers[2].complete(snap('root'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('diagnostics.tree')), findsOneWidget);
      expect(find.byKey(const Key('diagnostics.error')), findsNothing);
    });

    testWidgets('an injected controller drives the panel lifecycle keys', (
      tester,
    ) async {
      final List<Completer<TreeSnapshot>> completers =
          <Completer<TreeSnapshot>>[];
      Future<TreeSnapshot> loader() {
        final Completer<TreeSnapshot> c = Completer<TreeSnapshot>();
        completers.add(c);
        return c.future;
      }

      final DiagnosticsPanelController controller = DiagnosticsPanelController(
        loader: loader,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: DiagnosticsPanel(loader: loader, controller: controller),
        ),
      );
      await tester.pump();
      expect(completers, hasLength(1));
      expect(find.byKey(const Key('diagnostics.loading')), findsOneWidget);
      completers.single.complete(snap('root'));
      await tester.pumpAndSettle();
      expect(controller.value, isA<DiagnosticsLoaded>());
      expect(find.byKey(const Key('diagnostics.tree')), findsOneWidget);
    });

    test('a stale earlier success is suppressed', () async {
      final List<Completer<TreeSnapshot>> completers =
          <Completer<TreeSnapshot>>[];
      final DiagnosticsPanelController controller = DiagnosticsPanelController(
        loader: () {
          final Completer<TreeSnapshot> c = Completer<TreeSnapshot>();
          completers.add(c);
          return c.future;
        },
      );
      addTearDown(controller.dispose);
      final Future<void> first = controller.refresh();
      final Future<void> second = controller.refresh();
      completers[1].complete(snap('fresh'));
      await second;
      expect(
        (controller.value as DiagnosticsLoaded).snapshot.root.id,
        'fresh',
      );
      // The FIRST (stale) load completes afterwards — it must not clobber
      // the newer result.
      completers[0].complete(snap('stale'));
      await first;
      expect(
        (controller.value as DiagnosticsLoaded).snapshot.root.id,
        'fresh',
      );
    });

    test('a stale earlier failure is suppressed', () async {
      final List<Completer<TreeSnapshot>> completers =
          <Completer<TreeSnapshot>>[];
      final DiagnosticsPanelController controller = DiagnosticsPanelController(
        loader: () {
          final Completer<TreeSnapshot> c = Completer<TreeSnapshot>();
          completers.add(c);
          return c.future;
        },
      );
      addTearDown(controller.dispose);
      final Future<void> first = controller.refresh();
      final Future<void> second = controller.refresh();
      completers[1].complete(snap('fresh'));
      await second;
      // The FIRST (stale) load fails afterwards — the loaded state stays.
      completers[0].completeError(StateError('stale failure'));
      await first;
      expect(controller.value, isA<DiagnosticsLoaded>());
      expect(
        (controller.value as DiagnosticsLoaded).snapshot.root.id,
        'fresh',
      );
    });

    testWidgets(
      'switching back to Conversation retains the transcript and composer',
      (tester) async {
        final Completer<TreeSnapshot> pending = Completer<TreeSnapshot>();
        await tester.pumpWidget(shell(() => pending.future));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('transcript.idle')), findsOneWidget);

        await tester.tap(find.text('Diagnostics'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byKey(const Key('diagnostics.loading')), findsOneWidget);

        await tester.tap(find.text('Conversation'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(find.byKey(const Key('transcript.idle')), findsOneWidget);
        expect(find.byKey(const Key('prompt.goal')), findsOneWidget);
        expect(find.byKey(const Key('runStatus.idle')), findsOneWidget);
      },
    );
  });
}
