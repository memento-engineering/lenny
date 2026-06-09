/// End-to-end regression for the chat transcript wiring (lenny-wisp-0go2a.2).
///
/// The redesign's headline feature — the live transcript of a running
/// session — shipped broken because `PromptTabMount` published the trajectory
/// sink to the shell BEFORE `start()`, when `c.trajectory` was still
/// `Stream.empty()` and the host session was still null. The shell's
/// `_onTrajectoryChanged` fired once on that empty assignment, saw a null
/// session, returned early, and never fired again — so the
/// `ConversationViewModel` was never built and the transcript stayed on its
/// idle placeholder forever.
///
/// The isolated `conversation_view_model_test` / `transcript_list_test` passed
/// because they inject the turn/trajectory streams directly, and
/// `prompt_tab_mount_test` "mirrors" the `_onStart` hook with copied logic
/// instead of exercising it. Nothing drove the real
/// shell → controller → session wiring. This test does: it presses Start on
/// the actual shell and asserts the transcript comes alive. It fails before
/// the fix (VM never built → still idle) and passes after.
library;

import 'dart:async';

import 'package:exploration_agent/exploration_agent.dart';
import 'package:exploration_devtools/src/exploration_shell.dart';
import 'package:exploration_devtools/src/panels/model_catalog.dart';
import 'package:exploration_devtools/src/panels/provider_config.dart';
import 'package:exploration_devtools/src/panels/provider_config_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Fake session whose `turnEvents` we drive by hand. Unlike the
/// `prompt_tab_mount_test` fake, this one exposes [turnEvents] (and an
/// [emitTurn] helper) because the transcript wiring reads
/// `session.turnEvents` off the host's live session.
class _FakeSession implements ExplorationSession {
  final StreamController<SessionProgressEvent> _progress =
      StreamController<SessionProgressEvent>.broadcast();
  final StreamController<TurnEvent> _turns =
      StreamController<TurnEvent>.broadcast();
  Completer<SessionTermination>? runCompleter;
  bool _started = false;
  bool _ended = false;

  @override
  Stream<SessionProgressEvent> get progress => _progress.stream;

  @override
  Stream<TurnEvent> get turnEvents => _turns.stream;

  void emitTurn(TurnEvent e) => _turns.add(e);

  @override
  HandshakeResult get handshake => const HandshakeResult(
    contractVersion: '1.0',
    plugins: <PluginManifestEntry>[],
  );

  @override
  Future<void> start(String goal, ExplorationConfig config) async {
    _started = true;
    _progress.add(SessionStarted(goal));
  }

  @override
  Future<SessionTermination> run({
    required LoopHost host,
    required ModelProvider provider,
    required TrajectoryWriter writer,
    ConversationBuilder? conversation,
    ActionValidator? validator,
    int tokenBudget = 32000,
    Duration? turnBudget,
  }) {
    runCompleter ??= Completer<SessionTermination>();
    return runCompleter!.future;
  }

  @override
  Future<void> end() async {
    if (_ended) return;
    _ended = true;
    if (_started) _progress.add(const SessionEnded());
    await _progress.close();
    await _turns.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'transcript comes alive after Start: VM built, then renders an entry on '
    'the first turn event',
    (tester) async {
      // Roomy surface so the stacked transcript + prompt columns both lay out
      // without RenderFlex overflow and Start is hit-testable.
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fake = _FakeSession();

      final store = InMemoryProviderConfigStore();
      await store.save(
        SwiftInferUiConfig(
          bearerToken: 't',
          endpoint: Uri.parse('http://localhost:8080'),
          defaultModelId: 'qwen3.6-35b-a3b-8bit',
        ),
      );
      // Catalog hard-fails so we recover a selectable model via the fallback
      // link (the established seam) — keeps the test off real /v1/models JSON.
      final catalog = ModelCatalog(
        client: MockClient(
          (req) async => throw http.ClientException('Failed to fetch', req.url),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ExplorationShell(
            manifestProbe: () async => const <PluginManifestEntry>[],
            sessionFactory: () async => fake,
            store: store,
            catalog: catalog,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No session yet → idle transcript placeholder.
      expect(find.byKey(const Key('transcript.idle')), findsOneWidget);

      // Recover a selectable model so Start is enabled.
      await tester.ensureVisible(
        find.byKey(const Key('prompt.modelsError.useFallback')),
      );
      await tester.tap(find.byKey(const Key('prompt.modelsError.useFallback')));
      await tester.pumpAndSettle();

      // Goal is required (prompt.goal has a non-empty validator) — fill it or
      // _submit() bails before calling onStart.
      await tester.ensureVisible(find.byKey(const Key('prompt.goal')));
      await tester.enterText(
        find.byKey(const Key('prompt.goal')),
        'tap the accept button',
      );
      await tester.pumpAndSettle();

      // Press Start.
      await tester.ensureVisible(find.byKey(const Key('prompt.start')));
      await tester.tap(find.byKey(const Key('prompt.start')));
      await tester.pumpAndSettle();

      // The session is live → the ConversationViewModel is built and the
      // transcript shows its active-but-empty state (NOT the idle text). This is
      // the assertion that FAILS before the fix: the VM was never built, so the
      // shell stayed on `transcript.idle`.
      expect(find.byKey(const Key('transcript.idle')), findsNothing);
      expect(find.byKey(const Key('transcript.empty')), findsOneWidget);

      // Emit the first turn's reasoning — the VM must materialize an entry.
      fake.emitTurn(
        const TurnThinking(0, ThinkingDelta(text: 'hello', isFinal: false)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('transcript.empty')), findsNothing);
      expect(find.byKey(const Key('transcript.list')), findsOneWidget);
      expect(find.byKey(const ValueKey('entry.0')), findsOneWidget);

      // Unblock the controller's dispose() (it awaits `run`) at teardown.
      fake.runCompleter?.complete(
        const SessionTermination(SessionOutcome.done, finalSummary: ''),
      );
      await tester.pumpAndSettle();
    },
  );
}
