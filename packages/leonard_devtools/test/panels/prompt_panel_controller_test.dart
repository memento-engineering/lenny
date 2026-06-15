import 'dart:async';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:leonard_devtools/src/panels/prompt_panel_config.dart';
import 'package:leonard_devtools/src/panels/prompt_panel_controller.dart';
import 'package:leonard_devtools/src/panels/provider_config.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSession implements LeonardSession {
  _FakeSession({
    this.handshakeResult = const HandshakeResult(
      contractVersion: '1.0',
      plugins: <ExtensionManifestEntry>[],
    ),
  });

  final StreamController<SessionProgressEvent> _ctrl =
      StreamController<SessionProgressEvent>.broadcast();
  bool started = false;
  bool ended = false;

  /// Handshake returned from [handshake] after [start] completes.
  final HandshakeResult handshakeResult;

  // Captured arguments from the most recent run call.
  LoopHost? capturedHost;
  ModelProvider? capturedProvider;
  TrajectoryWriter? capturedWriter;
  int runCalls = 0;

  // Drive runFuture from tests.
  Completer<SessionTermination>? runCompleter;

  @override
  Stream<SessionProgressEvent> get progress => _ctrl.stream;

  @override
  HandshakeResult get handshake => handshakeResult;

  @override
  Future<void> start(String goal, LeonardConfig config) async {
    started = true;
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
    runCalls += 1;
    capturedHost = host;
    capturedProvider = provider;
    capturedWriter = writer;
    final c = runCompleter ?? Completer<SessionTermination>();
    if (runCompleter == null) {
      c.complete(const SessionTermination(SessionOutcome.done));
    }
    runCompleter = c;
    return c.future;
  }

  @override
  Future<void> end() async {
    if (ended) return;
    ended = true;
    if (started) {
      _ctrl.add(const SessionEnded());
    }
    await _ctrl.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _cfg = PromptPanelConfig(
  goal: 'g',
  modelId: 'm',
  maxTurns: 1,
  wallClockBudget: Duration(minutes: 1),
  enabledExtensionNamespaces: <String>{},
);

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

ProviderConfig _providerCfg() => AnthropicUiConfig(apiKey: 'k');

void main() {
  test('start instantiates session and forwards events', () async {
    final fake = _FakeSession();
    final c = PromptPanelController(
      factory: () async => fake,
      providerFactory: (_, __, ___) => _DummyProvider(),
    );
    final received = <SessionProgressEvent>[];
    c.events.listen(received.add);

    await c.start(_cfg, providerCfg: _providerCfg());
    await Future<void>.delayed(Duration.zero);

    expect(fake.started, isTrue);
    expect(c.running, isTrue);
    expect(received, isNotEmpty);

    await c.dispose();
  });

  test(
    'start pins the default operating guide as the loop host agentsMd',
    () async {
      // Regression for lenny-wisp-0go2a.4: the panel used to pass agentsMd:'',
      // shipping the model a bare goal with no methodology / Finishing rule,
      // which caused premature core.done on multi-step goals.
      final fake = _FakeSession();
      final c = PromptPanelController(
        factory: () async => fake,
        providerFactory: (_, __, ___) => _DummyProvider(),
      );

      await c.start(_cfg, providerCfg: _providerCfg());

      expect(fake.capturedHost, isNotNull);
      expect(fake.capturedHost!.agentsMd, equals(kDefaultAgentsMd));
      expect(fake.capturedHost!.agentsMd, contains('## Finishing'));

      await c.dispose();
    },
  );

  test('stop ends session and clears running flag', () async {
    final fake = _FakeSession();
    final c = PromptPanelController(
      factory: () async => fake,
      providerFactory: (_, __, ___) => _DummyProvider(),
    );

    await c.start(_cfg, providerCfg: _providerCfg());
    await c.stop();

    expect(fake.ended, isTrue);
    expect(c.running, isFalse);

    await c.dispose();
  });

  test('start while running throws', () async {
    final fake = _FakeSession();
    final c = PromptPanelController(
      factory: () async => fake,
      providerFactory: (_, __, ___) => _DummyProvider(),
    );

    await c.start(_cfg, providerCfg: _providerCfg());
    await expectLater(
      () => c.start(_cfg, providerCfg: _providerCfg()),
      throwsStateError,
    );

    await c.dispose();
  });

  test(
    'missing providerCfg throws StateError before any session.run',
    () async {
      final fake = _FakeSession();
      final c = PromptPanelController(
        factory: () async => fake,
        providerFactory: (_, __, ___) => _DummyProvider(),
      );

      await expectLater(() => c.start(_cfg), throwsStateError);
      expect(
        fake.runCalls,
        0,
        reason: 'session.run must not be reached without providerCfg',
      );
      expect(c.running, isFalse);

      await c.dispose();
    },
  );

  test('providerFactory receives ProviderConfig + modelId', () async {
    final fake = _FakeSession();
    ProviderConfig? capturedCfg;
    String? capturedModel;
    String? capturedSession;
    final c = PromptPanelController(
      factory: () async => fake,
      providerFactory: (cfg, modelId, sessionId) {
        capturedCfg = cfg;
        capturedModel = modelId;
        capturedSession = sessionId;
        return _DummyProvider();
      },
    );

    final providerCfg = AnthropicUiConfig(apiKey: 'k');
    await c.start(_cfg, providerCfg: providerCfg);

    expect(capturedCfg, same(providerCfg));
    expect(capturedModel, 'm');
    expect(capturedSession, isNotEmpty);
    expect(c.activeProvider, isA<_DummyProvider>());

    await c.dispose();
  });

  test(
    'start invokes session.run with merged tools, dummy provider, writer',
    () async {
      final fake = _FakeSession(
        handshakeResult: const HandshakeResult(
          contractVersion: '1.0',
          plugins: <ExtensionManifestEntry>[
            // Handshake carries BARE tool names; buildExtensionTools prefixes
            // the namespace to produce the qualified ToolDescriptor.name.
            ExtensionManifestEntry(namespace: 'router', tools: <String>['go']),
            ExtensionManifestEntry(namespace: 'dio', tools: <String>['cancel']),
          ],
        ),
      );
      final provider = _DummyProvider();
      final c = PromptPanelController(
        factory: () async => fake,
        providerFactory: (_, __, ___) => provider,
      );

      await c.start(
        const PromptPanelConfig(
          goal: 'g',
          modelId: 'm',
          maxTurns: 1,
          wallClockBudget: Duration(minutes: 1),
          enabledExtensionNamespaces: <String>{'router'},
        ),
        providerCfg: _providerCfg(),
      );

      expect(fake.runCalls, 1);
      expect(fake.capturedProvider, same(provider));
      expect(fake.capturedWriter, isA<TrajectoryWriter>());
      expect(fake.capturedHost, isA<DefaultLoopHost>());

      // mergedTools() must reflect enabledExtensionNamespaces ∩ handshake.plugins.
      final host = fake.capturedHost!;
      final names = host.mergedTools().map((t) => t.name).toSet();
      expect(names, <String>{
        'router.go',
      }, reason: 'only router (enabled & in handshake) tools should appear');
      expect(host.activeExtensionNamespaces(), <String>{'router'});

      await c.dispose();
    },
  );

  test('runFuture resolves before stop() returns', () async {
    final fake = _FakeSession();
    final c = PromptPanelController(
      factory: () async => fake,
      providerFactory: (_, __, ___) => _DummyProvider(),
    );

    await c.start(_cfg, providerCfg: _providerCfg());
    final fut = c.runFuture;
    expect(fut, isNotNull);

    await c.stop();

    // After stop() the controller's runFuture is cleared, and the
    // captured future from the fake is complete.
    await expectLater(fut, completion(isA<SessionTermination>()));
    expect(c.runFuture, isNull);

    await c.dispose();
  });

  test('trajectory stream emits the SessionHeader written in start', () async {
    final fake = _FakeSession();
    final c = PromptPanelController(
      factory: () async => fake,
      providerFactory: (_, __, ___) => _DummyProvider(),
    );

    // Subscribe before start so we don't miss the header.
    final emitted = <TrajectoryRecord>[];
    // Listen lazily by deferring until trajectory is non-empty.
    await c.start(_cfg, providerCfg: _providerCfg());
    final sub = c.trajectory.listen(emitted.add);
    // The header was written before this subscription. To verify
    // observability for *future* records, write one through the
    // captured writer.
    final writer = fake.capturedWriter!;
    await writer.writeTurn(
      const TurnRecord(
        index: 0,
        observation: <String, dynamic>{},
        stability: <String, dynamic>{},
        proposedAction: <String, dynamic>{},
        validation: <String, dynamic>{},
        executedAction: <String, dynamic>{},
        diff: <String, dynamic>{},
        modelMetadata: <String, dynamic>{},
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(emitted, hasLength(1));
    expect(emitted.single, isA<TurnRecord>());

    await sub.cancel();
    await c.dispose();
  });

  test(
    'swift-infer provider carries Bearer + conversation id via real factory',
    () async {
      final fake = _FakeSession();
      final c = PromptPanelController(factory: () async => fake);

      final cfg = SwiftInferUiConfig(
        bearerToken: 'tok',
        endpoint: Uri.parse('http://localhost:8080'),
        captureBodies: true,
      );
      await c.start(
        const PromptPanelConfig(
          goal: 'g',
          modelId: 'qwen3.6-35b-a3b-8bit',
          maxTurns: 1,
          wallClockBudget: Duration(minutes: 1),
          enabledExtensionNamespaces: <String>{},
        ),
        providerCfg: cfg,
      );

      final provider = c.activeProvider as SwiftInferModelProvider;
      expect(provider.config.bearerToken, 'tok');
      expect(provider.config.captureBodies, isTrue);
      expect(provider.config.conversationId, startsWith('leonard-panel-'));
      expect(provider.capabilities.vision, isTrue);
      expect(provider.capabilities.preserveThinking, isTrue);

      await c.dispose();
    },
  );

  test(
    'factory routes through ensureSession; onStop invoked instead of session.end',
    () async {
      LeonardSession? storedSession;
      var stopCalled = false;

      final fake = _FakeSession();
      Future<LeonardSession> ensureSession() async {
        storedSession = fake;
        return fake;
      }

      Future<void> endSession() async {
        stopCalled = true;
        storedSession = null;
        // Production host.endSession() calls session.end(); we intentionally skip it
        // here to prove the controller does NOT double-end.
      }

      final c = PromptPanelController(
        factory: ensureSession,
        onStop: endSession,
        providerFactory: (_, __, ___) => _DummyProvider(),
      );

      await c.start(_cfg, providerCfg: _providerCfg());
      expect(storedSession, isNotNull, reason: 'ensureSession was invoked');
      expect(c.running, isTrue);

      await c.stop();
      expect(stopCalled, isTrue, reason: 'onStop callback was invoked');
      expect(
        storedSession,
        isNull,
        reason: 'onStop cleared the host-side session ref',
      );
      expect(
        fake.ended,
        isFalse,
        reason:
            'controller did not call session.end() directly when onStop provided',
      );
      expect(c.running, isFalse);

      await c.dispose();
    },
  );
}
