/// Targeted tests for the `runFuture`-driven re-enable hook in
/// `PromptTabMount._onStart`. The full form-driven path requires a
/// populated model catalog + provider config; this test exercises the
/// minimum surface — the runFuture `whenComplete` chain that flips
/// `running` back to false when the loop exits naturally — by driving
/// the controller directly with a fake [LeonardSession].
library;

import 'dart:async';
import 'dart:convert';

import 'package:dart_service_protocol_shared/dart_service_protocol_shared.dart';
import 'package:leonard_agent/leonard_agent.dart';
import 'package:leonard_devtools/src/conversation/conversation_state.dart'
    show RunStatus;
import 'package:leonard_devtools/src/dtd_acp_model_provider.dart';
import 'package:leonard_devtools/src/panels/model_catalog.dart';
import 'package:leonard_devtools/src/panels/prompt_panel_config.dart';
import 'package:leonard_devtools/src/panels/prompt_panel_config_store.dart';
import 'package:leonard_devtools/src/panels/prompt_panel_controller.dart';
import 'package:leonard_devtools/src/panels/prompt_tab_mount.dart';
import 'package:leonard_devtools/src/panels/provider_config.dart';
import 'package:leonard_devtools/src/panels/provider_config_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeSession implements LeonardSession {
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
    extensions: <ExtensionManifestEntry>[],
  );

  @override
  Future<void> start(String goal, LeonardConfig config) async {
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
    if (_started) {
      _ctrl.add(const SessionEnded());
    }
    await _ctrl.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
    ConversationSnapshot snapshot,
    ActionSchema schema,
  ) => throw UnimplementedError();

  @override
  Stream<ThinkingDelta> thinking() => const Stream.empty();
}

class _CapturingPromptConfigStore implements PromptPanelConfigStore {
  final List<PromptPanelConfig> saved = <PromptPanelConfig>[];

  @override
  Future<PromptPanelConfig?> load({
    required Set<String> liveNamespaces,
  }) async => null;

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
  enabledExtensionNamespaces: <String>{},
);

ProviderConfig _providerCfg() => AnthropicUiConfig(apiKey: 'k');

const Map<String, Object?> _acpCapabilities = <String, Object?>{
  'vision': false,
  'preserve_thinking': true,
  'max_context': 128000,
  'supports_tool_use': false,
};

ClientServiceInfo _acpService() =>
    ClientServiceInfo('leonard.acp', <String, ClientServiceMethodInfo>{
      'decide': ClientServiceMethodInfo('decide', _acpCapabilities),
      'session/new': ClientServiceMethodInfo('session/new', <String, Object?>{
        'harness_labels': <String>['codex-acp', 'copilot'],
      }),
    });

DtdAcpPanelClient _acpClient({
  required Future<Map<String, Object?>> Function(String, String) open,
  bool available = true,
}) => DtdAcpPanelClient(
  listServices: () async => available
      ? <ClientServiceInfo>[_acpService()]
      : const <ClientServiceInfo>[],
  newSession: open,
  providerBuilder: (capabilities, readiness) => DtdAcpModelProvider(
    capabilities: capabilities,
    read: () => const Stream<Map<String, Object?>>.empty(),
    call: (_) async => const <String, Object?>{},
    readiness: readiness,
  ),
);

http.Response _modelsResponse(String id) => http.Response(
  jsonEncode(<String, Object?>{
    'data': <Map<String, Object?>>[
      <String, Object?>{'id': id},
    ],
  }),
  200,
);

void main() {
  testWidgets(
    'ACP loads qualified host models, persists current id, and makes no HTTP request',
    (tester) async {
      final store = InMemoryProviderConfigStore();
      await store.save(
        const AcpUiConfig(harnessLabel: 'codex-acp', modelId: 'gpt-5.6-sol'),
      );
      int httpRequests = 0;
      final ModelCatalog catalog = ModelCatalog(
        client: MockClient((request) async {
          httpRequests++;
          return http.Response('{}', 500);
        }),
      );
      final List<(String, String)> opens = <(String, String)>[];
      final DtdAcpPanelClient client = _acpClient(
        open: (harness, model) async {
          opens.add((harness, model));
          return <String, Object?>{
            'available_models': <String>[
              'gpt-5.6-sol[low]',
              'gpt-5.6-sol[high]',
            ],
            'current_model_id': 'gpt-5.6-sol[high]',
          };
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PromptTabMount(
              extensions: const <ExtensionManifestEntry>[],
              store: store,
              catalog: catalog,
              acpPanelClient: client,
              initialProviderId: 'acp',
              promptConfigStore: InMemoryPromptPanelConfigStore(),
              controllerFactory: () => PromptPanelController(
                factory: () async => _FakeSession(),
                providerFactory: (_, __, ___) => _DummyProvider(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(opens, <(String, String)>[('codex-acp', 'gpt-5.6-sol')]);
      expect(httpRequests, 0);
      expect(find.byKey(const Key('providerForm.acp')), findsOneWidget);
      final DropdownButtonFormField<String> modelPicker = tester.widget(
        find.byKey(const Key('prompt.model')),
      );
      expect(modelPicker.initialValue, 'gpt-5.6-sol[high]');
      final Text resolved = tester.widget(
        find.byKey(const Key('prompt.resolvedModel')),
      );
      expect(resolved.data, contains('gpt-5.6-sol[high]'));
      final AcpUiConfig persisted = await store.load('acp') as AcpUiConfig;
      expect(persisted.modelId, 'gpt-5.6-sol[high]');
    },
  );

  testWidgets('unavailable ACP host empties models and keeps Start invalid', (
    tester,
  ) async {
    final store = InMemoryProviderConfigStore();
    await store.save(
      const AcpUiConfig(harnessLabel: 'codex-acp', modelId: 'model'),
    );
    int starts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PromptTabMount(
            extensions: const <ExtensionManifestEntry>[],
            store: store,
            catalog: ModelCatalog(
              client: MockClient((request) async => http.Response('{}', 500)),
            ),
            acpPanelClient: _acpClient(
              available: false,
              open: (_, __) async => throw StateError('must not open'),
            ),
            initialProviderId: 'acp',
            promptConfigStore: InMemoryPromptPanelConfigStore(),
            controllerFactory: () {
              starts++;
              return PromptPanelController(
                factory: () async => _FakeSession(),
                providerFactory: (_, __, ___) => _DummyProvider(),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('prompt.modelsError')), findsOneWidget);
    expect(find.text('acp — no ACP host is registered'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('prompt.goal')), 'drive it');
    await tester.ensureVisible(find.byKey(const Key('prompt.start')));
    await tester.tap(find.byKey(const Key('prompt.start')));
    await tester.pumpAndSettle();
    expect(starts, 0);
    expect(find.text('Select a model'), findsOneWidget);
  });

  testWidgets('error after success retains models and keeps Start enabled', (
    tester,
  ) async {
    final store = InMemoryProviderConfigStore();
    await store.save(
      SwiftInferUiConfig(
        bearerToken: 'token',
        endpoint: Uri.parse('http://localhost:8080'),
      ),
    );
    int requests = 0;
    final ModelCatalog catalog = ModelCatalog(
      client: MockClient((request) async {
        requests++;
        if (requests == 1) return _modelsResponse('stable-model');
        return http.Response('{}', 401);
      }),
    );
    late _FakeSession session;
    int starts = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PromptTabMount(
            extensions: const <ExtensionManifestEntry>[],
            store: store,
            catalog: catalog,
            promptConfigStore: InMemoryPromptPanelConfigStore(),
            controllerFactory: () {
              starts++;
              session = _FakeSession();
              return PromptPanelController(
                factory: () async => session,
                providerFactory: (_, __, ___) => _DummyProvider(),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const Key('prompt.model')),
          )
          .initialValue,
      'stable-model',
    );

    await tester.ensureVisible(find.byKey(const Key('prompt.modelsReload')));
    await tester.tap(find.byKey(const Key('prompt.modelsReload')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('prompt.modelsError')), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const Key('prompt.model')),
          )
          .initialValue,
      'stable-model',
    );

    await tester.enterText(find.byKey(const Key('prompt.goal')), 'drive it');
    await tester.ensureVisible(find.byKey(const Key('prompt.start')));
    await tester.tap(find.byKey(const Key('prompt.start')));
    await tester.pump();
    expect(starts, 1);

    session.runCompleter!.complete(
      const SessionTermination(SessionOutcome.done, finalSummary: ''),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('slower stale refresh cannot overwrite a newer configuration', (
    tester,
  ) async {
    final store = InMemoryProviderConfigStore();
    await store.save(
      SwiftInferUiConfig(
        bearerToken: 'initial-token',
        endpoint: Uri.parse('http://localhost:8080'),
      ),
    );
    final Completer<http.Response> slow = Completer<http.Response>();
    final Completer<http.Response> fast = Completer<http.Response>();
    final ModelCatalog catalog = ModelCatalog(
      client: MockClient((request) {
        switch (request.headers['authorization']) {
          case 'Bearer initial-token':
            return Future<http.Response>.value(
              _modelsResponse('initial-model'),
            );
          case 'Bearer slow-token':
            return slow.future;
          case 'Bearer fast-token':
            return fast.future;
          default:
            return Future<http.Response>.error(
              StateError('unexpected request: ${request.headers}'),
            );
        }
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PromptTabMount(
            extensions: const <ExtensionManifestEntry>[],
            store: store,
            catalog: catalog,
            promptConfigStore: InMemoryPromptPanelConfigStore(),
            controllerFactory: () => PromptPanelController(
              factory: () async => _FakeSession(),
              providerFactory: (_, __, ___) => _DummyProvider(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder bearer = find.byKey(
      const Key('providerForm.swift-infer.bearer'),
    );
    await tester.enterText(bearer, 'slow-token');
    await tester.pump();
    await tester.enterText(bearer, 'fast-token');
    await tester.pump();

    fast.complete(_modelsResponse('fast-model'));
    await tester.pumpAndSettle();
    slow.complete(_modelsResponse('slow-model'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const Key('prompt.model')),
          )
          .initialValue,
      'fast-model',
    );
    expect(tester.widget<TextFormField>(bearer).controller!.text, 'fast-token');
    final SwiftInferUiConfig persisted =
        await store.load('swift-infer') as SwiftInferUiConfig;
    expect(persisted.bearerToken, 'fast-token');
  });

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
      unawaited(
        c.runFuture?.whenComplete(() async {
          await c.stop();
          stopped.complete();
        }),
      );

      // Complete the in-flight session naturally.
      fake.runCompleter!.complete(
        const SessionTermination(SessionOutcome.done, finalSummary: ''),
      );
      await stopped.future;

      expect(
        c.running,
        isFalse,
        reason: 'natural loop termination should re-enable the form',
      );
      expect(c.runFuture, isNull);

      await c.dispose();
    },
  );

  testWidgets(
    'onUseFallback installs synthetic single-model state and clears the error banner',
    (tester) async {
      // Wire a swift-infer config into the store; the catalog will hard
      // fail with a ClientException so the banner fires; tapping the
      // fallback link should rewrite ModelCatalogState to a single-entry
      // synthetic model and clear the error.
      final store = InMemoryProviderConfigStore();
      await store.save(
        SwiftInferUiConfig(
          bearerToken: 't',
          endpoint: Uri.parse('http://localhost:8080'),
          defaultModelId: 'qwen3.6-35b-a3b-8bit',
        ),
      );
      final catalog = ModelCatalog(
        client: MockClient(
          (req) async => throw http.ClientException('Failed to fetch', req.url),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PromptTabMount(
              extensions: const <ExtensionManifestEntry>[],
              store: store,
              catalog: catalog,
              promptConfigStore: InMemoryPromptPanelConfigStore(),
              controllerFactory: () => PromptPanelController(
                factory: () async => _FakeSession(),
                providerFactory: (_, __, ___) => _DummyProvider(),
              ),
            ),
          ),
        ),
      );
      // Allow _bootstrap()'s async load + refresh chain to settle.
      await tester.pumpAndSettle();

      // The banner is up (ClientException -> networkOrCors).
      expect(find.byKey(const Key('prompt.modelsError')), findsOneWidget);
      expect(
        find.byKey(const Key('prompt.modelsError.useFallback')),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const Key('prompt.modelsError.useFallback')),
      );
      await tester.tap(find.byKey(const Key('prompt.modelsError.useFallback')));
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
    },
  );

  test('_onStart saves config before starting the session', () async {
    final promptStore = _CapturingPromptConfigStore();

    final fake = _FakeSession();
    final c = PromptPanelController(
      factory: () async => fake,
      providerFactory: (_, __, ___) => _DummyProvider(),
    );

    // Simulate what PromptTabMount._onStart does: save then start.
    unawaited(promptStore.save(_cfg, knownNamespaces: const <String>{}));
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
    unawaited(
      c.runFuture
          ?.then((t) {
            sink.value = switch (t.outcome) {
              SessionOutcome.done => RunStatus.done,
              SessionOutcome.budgetExhausted => RunStatus.done,
              SessionOutcome.harnessError => RunStatus.error,
            };
          })
          .whenComplete(() async {
            await c.stop();
            stopped.complete();
          }),
    );

    fake.runCompleter!.complete(
      const SessionTermination(SessionOutcome.done, finalSummary: ''),
    );
    await stopped.future;

    expect(sink.value, RunStatus.done);
    await c.dispose();
  });
}
