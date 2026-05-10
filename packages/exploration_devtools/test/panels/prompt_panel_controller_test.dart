import 'dart:async';

import 'package:exploration_agent/exploration_agent.dart';
import 'package:exploration_devtools/src/panels/prompt_panel_config.dart';
import 'package:exploration_devtools/src/panels/prompt_panel_controller.dart';
import 'package:exploration_devtools/src/panels/provider_config.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSession implements ExplorationSession {
  final StreamController<SessionProgressEvent> _ctrl =
      StreamController<SessionProgressEvent>.broadcast();
  bool started = false;
  bool ended = false;

  @override
  Stream<SessionProgressEvent> get progress => _ctrl.stream;

  @override
  Future<void> start(String goal, ExplorationConfig config) async {
    started = true;
    _ctrl.add(SessionStarted(goal));
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
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

const _cfg = PromptPanelConfig(
  goal: 'g',
  modelId: 'm',
  maxTurns: 1,
  wallClockBudget: Duration(minutes: 1),
  enabledPluginNamespaces: {},
);

void main() {
  test('start instantiates session and forwards events', () async {
    final fake = _FakeSession();
    final c = PromptPanelController(
      vmServiceUri: Uri.parse('ws://x'),
      factory: (_) async => fake,
    );
    final received = <SessionProgressEvent>[];
    c.events.listen(received.add);

    await c.start(_cfg);
    await Future<void>.delayed(Duration.zero);

    expect(fake.started, isTrue);
    expect(c.running, isTrue);
    expect(received, isNotEmpty);

    await c.dispose();
  });

  test('stop ends session and clears running flag', () async {
    final fake = _FakeSession();
    final c = PromptPanelController(
      vmServiceUri: Uri.parse('ws://x'),
      factory: (_) async => fake,
    );

    await c.start(_cfg);
    await c.stop();

    expect(fake.ended, isTrue);
    expect(c.running, isFalse);

    await c.dispose();
  });

  test('start while running throws', () async {
    final fake = _FakeSession();
    final c = PromptPanelController(
      vmServiceUri: Uri.parse('ws://x'),
      factory: (_) async => fake,
    );

    await c.start(_cfg);
    await expectLater(() => c.start(_cfg), throwsStateError);

    await c.dispose();
  });

  test('providerFactory receives ProviderConfig + modelId', () async {
    final fake = _FakeSession();
    ProviderConfig? capturedCfg;
    String? capturedModel;
    String? capturedSession;
    final c = PromptPanelController(
      vmServiceUri: Uri.parse('ws://x'),
      factory: (_) async => fake,
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

  test('no providerCfg → no provider built', () async {
    final fake = _FakeSession();
    var called = false;
    final c = PromptPanelController(
      vmServiceUri: Uri.parse('ws://x'),
      factory: (_) async => fake,
      providerFactory: (_, __, ___) {
        called = true;
        return _DummyProvider();
      },
    );

    await c.start(_cfg);

    expect(called, isFalse);
    expect(c.activeProvider, isNull);

    await c.dispose();
  });

  test('swift-infer provider carries Bearer + conversation id via real factory',
      () async {
    final fake = _FakeSession();
    final c = PromptPanelController(
      vmServiceUri: Uri.parse('ws://x'),
      factory: (_) async => fake,
    );

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
        enabledPluginNamespaces: {},
      ),
      providerCfg: cfg,
    );

    final provider = c.activeProvider as SwiftInferModelProvider;
    expect(provider.config.bearerToken, 'tok');
    expect(provider.config.captureBodies, isTrue);
    expect(provider.config.conversationId, startsWith('exploration-panel-'));
    expect(provider.capabilities.vision, isTrue);
    expect(provider.capabilities.preserveThinking, isTrue);

    await c.dispose();
  });
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
  Future<ModelDecision> decide(PromptPayload prompt, ActionSchema schema) =>
      throw UnimplementedError();

  @override
  Stream<ThinkingDelta> thinking() => const Stream.empty();
}
