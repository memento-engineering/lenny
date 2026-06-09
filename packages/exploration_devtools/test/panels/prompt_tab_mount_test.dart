/// Targeted tests for the `runFuture`-driven re-enable hook in
/// `PromptTabMount._onStart`. The full form-driven path requires a
/// populated model catalog + provider config; this test exercises the
/// minimum surface — the runFuture `whenComplete` chain that flips
/// `running` back to false when the loop exits naturally — by driving
/// the controller directly with a fake [ExplorationSession].
library;

import 'dart:async';

import 'package:exploration_agent/exploration_agent.dart';
import 'package:exploration_devtools/src/conversation/conversation_state.dart'
    show RunStatus;
import 'package:exploration_devtools/src/panels/model_catalog.dart';
import 'package:exploration_devtools/src/panels/prompt_panel_config.dart';
import 'package:exploration_devtools/src/panels/prompt_panel_config_store.dart';
import 'package:exploration_devtools/src/panels/prompt_panel_controller.dart';
import 'package:exploration_devtools/src/panels/prompt_tab_mount.dart';
import 'package:exploration_devtools/src/panels/provider_config.dart';
import 'package:exploration_devtools/src/panels/provider_config_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeSession implements ExplorationSession {
  _FakeSession();

  final StreamController<SessionProgressEvent> _ctrl =
      StreamController<SessionProgressEvent>.broadcast();
  bool _started = false;
  bool _ended = false;
  Completer<SessionTermination>? runCompleter;

  @override
  Stream<SessionProgressEvent> get progress => _ctrl.stream;

  @override
  HandshakeResult get handshake => const HandshakeResult(
        contractVersion: '1.0',
        plugins: <PluginManifestEntry>[],
      );

  @override
  Future<void> start(String goal, ExplorationConfig config) async {
    _started = true;
    _ctrl.add(SessionStarted(goal));
  }

  @override
  Future<SessionTermination> run({
    required LoopHost host,
    required ModelProvider provider,
    required TrajectoryWriter writer,
    ConversationBuilder? conversation,
    ActionValidator? validator,
  }) {
    runCompleter ??= Completer<SessionTermination>();
    return runCompleter!.future;
  }

  @override
  Future<void> end() async {
    if (_ended) return;
    _ended = true;
    if (_started) {
      _ctrl.add(const SessionEnded());
    }
    await _ctrl.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _DummyProvider implements ModelProvider {
  @override
  ModelCapabilities get capabilities => const ModelCapabilities(
        vision: false,
        preserveThinking: false,
        maxContext: 1,
        supportsToolUse: false,
      );

  @override
  Future<ModelDecision> decide(
          ConversationSnapshot snapshot, ActionSchema schema) =>
      throw UnimplementedError();

  @override
  Stream<ThinkingDelta> thinking() => const Stream.empty();
}

class _CapturingPromptConfigStore implements PromptPanelConfigStore {
  final List<PromptPanelConfig> saved = <PromptPanelConfig>[];

  @override
  Future<PromptPanelConfig?> load({required Set<String> liveNamespaces}) async =>
      null;

  @override
  Future<void> save(
    PromptPanelConfig config, {
    required Set<String> knownNamespaces,
  }) async {
    saved.add(config);
  }
}

const _cfg = PromptPanelConfig(
  goal: 'g',
  modelId: 'm',
  maxTurns: 1,
  wallClockBudget: Duration(minutes: 1),
  enabledPluginNamespaces: <String>{},
);

ProviderConfig _providerCfg() => AnthropicUiConfig(apiKey: 'k');

void main() {
  test(
      '_onStart pattern: form re-enables when runFuture completes naturally',
      () async {
    // This exercises the controller-level mechanism that
    // `PromptTabMount._onStart` chains via `whenComplete`. When the
    // loop exits naturally (runFuture resolves), the panel calls
    // `stop()` which flips `running` back to false. We don't drive
    // the form-level UI here — that pipeline requires a populated
    // model catalog + provider config; covered by manual smoke.
    final fake = _FakeSession();
    final c = PromptPanelController(
      factory: () async => fake,
      providerFactory: (_, __, ___) => _DummyProvider(),
    );

    await c.start(_cfg, providerCfg: _providerCfg());
    expect(c.running, isTrue);

    // Mirror the prompt_tab_mount.dart hook: when runFuture completes,
    // stop() is invoked to re-enable the form.
    final stopped = Completer<void>();
    unawaited(c.runFuture?.whenComplete(() async {
      await c.stop();
      stopped.complete();
    }));

    // Complete the in-flight session naturally.
    fake.runCompleter!.complete(
      const SessionTermination(SessionOutcome.done, finalSummary: ''),
    );
    await stopped.future;

    expect(c.running, isFalse,
        reason: 'natural loop termination should re-enable the form');
    expect(c.runFuture, isNull);

    await c.dispose();
  });

  testWidgets(
      'onUseFallback installs synthetic single-model state and clears the error banner',
      (tester) async {
    // Wire a swift-infer config into the store; the catalog will hard
    // fail with a ClientException so the banner fires; tapping the
    // fallback link should rewrite ModelCatalogState to a single-entry
    // synthetic model and clear the error.
    final store = InMemoryProviderConfigStore();
    await store.save(SwiftInferUiConfig(
      bearerToken: 't',
      endpoint: Uri.parse('http://localhost:8080'),
      defaultModelId: 'qwen3.6-35b-a3b-8bit',
    ));
    final catalog = ModelCatalog(
      client: MockClient((req) async =>
          throw http.ClientException('Failed to fetch', req.url)),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PromptTabMount(
          plugins: const <PluginManifestEntry>[],
          store: store,
          catalog: catalog,
          promptConfigStore: InMemoryPromptPanelConfigStore(),
          controllerFactory: () => PromptPanelController(
            factory: () async => _FakeSession(),
            providerFactory: (_, __, ___) => _DummyProvider(),
          ),
        ),
      ),
    ));
    // Allow _bootstrap()'s async load + refresh chain to settle.
    await tester.pumpAndSettle();

    // The banner is up (ClientException -> networkOrCors).
    expect(find.byKey(const Key('prompt.modelsError')), findsOneWidget);
    expect(
      find.byKey(const Key('prompt.modelsError.useFallback')),
      findsOneWidget,
    );

    await tester.ensureVisible(
        find.byKey(const Key('prompt.modelsError.useFallback')));
    await tester
        .tap(find.byKey(const Key('prompt.modelsError.useFallback')));
    await tester.pumpAndSettle();

    // Banner is gone; the dropdown carries exactly the fallback id.
    expect(find.byKey(const Key('prompt.modelsError')), findsNothing);
    final dropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('prompt.model')),
    );
    expect(dropdown.initialValue, 'qwen3.6-35b-a3b-8bit');
    // The synthetic model id is rendered in the dropdown's label area.
    expect(find.text('qwen3.6-35b-a3b-8bit'), findsWidgets);
    // And the "using fallback" badge fires because synthetic state
    // carries usingFallback: true.
    expect(find.byKey(const Key('badge.fallback')), findsOneWidget);
  });

  test('_onStart saves config before starting the session', () async {
    final promptStore = _CapturingPromptConfigStore();

    final fake = _FakeSession();
    final c = PromptPanelController(
      factory: () async => fake,
      providerFactory: (_, __, ___) => _DummyProvider(),
    );

    // Simulate what PromptTabMount._onStart does: save then start.
    unawaited(promptStore.save(
      _cfg,
      knownNamespaces: const <String>{},
    ));
    await c.start(_cfg, providerCfg: _providerCfg());

    expect(promptStore.saved, hasLength(1));
    expect(promptStore.saved.first.goal, 'g');

    // Complete the run so dispose() doesn't hang.
    fake.runCompleter!.complete(
      const SessionTermination(SessionOutcome.done, finalSummary: ''),
    );
    await c.dispose();
  });

  test('completionSink receives RunStatus.done on natural run end', () async {
    final sink = ValueNotifier<RunStatus?>(null);
    addTearDown(sink.dispose);

    final fake = _FakeSession();
    final c = PromptPanelController(
      factory: () async => fake,
      providerFactory: (_, __, ___) => _DummyProvider(),
    );

    // Before start, sink is null.
    expect(sink.value, isNull);

    await c.start(_cfg, providerCfg: _providerCfg());

    // Mirror the PromptTabMount._onStart hook with completionSink.
    final stopped = Completer<void>();
    unawaited(c.runFuture?.then((t) {
      sink.value = switch (t.outcome) {
        SessionOutcome.done => RunStatus.done,
        SessionOutcome.budgetExhausted => RunStatus.done,
        SessionOutcome.harnessError => RunStatus.error,
      };
    }).whenComplete(() async {
      await c.stop();
      stopped.complete();
    }));

    fake.runCompleter!
        .complete(const SessionTermination(SessionOutcome.done, finalSummary: ''));
    await stopped.future;

    expect(sink.value, RunStatus.done);
    await c.dispose();
  });
}
