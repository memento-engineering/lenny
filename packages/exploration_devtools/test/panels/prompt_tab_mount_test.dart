/// Targeted tests for the `runFuture`-driven re-enable hook in
/// `PromptTabMount._onStart`. The full form-driven path requires a
/// populated model catalog + provider config; this test exercises the
/// minimum surface — the runFuture `whenComplete` chain that flips
/// `running` back to false when the loop exits naturally — by driving
/// the controller directly with a fake [ExplorationSession].
library;

import 'dart:async';

import 'package:exploration_agent/exploration_agent.dart';
import 'package:exploration_devtools/src/panels/prompt_panel_config.dart';
import 'package:exploration_devtools/src/panels/prompt_panel_controller.dart';
import 'package:exploration_devtools/src/panels/provider_config.dart';
import 'package:flutter_test/flutter_test.dart';

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
    PromptAssembler? assembler,
    ActionValidator? validator,
    RunningSummary? summary,
    ActionRing? actions,
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
  Future<ModelDecision> decide(PromptPayload prompt, ActionSchema schema) =>
      throw UnimplementedError();

  @override
  Stream<ThinkingDelta> thinking() => const Stream.empty();
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
}
