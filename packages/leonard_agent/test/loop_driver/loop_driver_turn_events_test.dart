import 'dart:async';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

class _MemorySink extends TrajectorySink {
  final List<String> lines = <String>[];
  bool closed = false;

  @override
  Future<void> writeLine(String line) async => lines.add(line);

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async => closed = true;
}

class _ThinkingProvider extends ModelProvider {
  _ThinkingProvider({required this.chunks, required this.decision});

  final List<String> chunks;
  final ModelDecision decision;

  @override
  ModelCapabilities get capabilities => const ModelCapabilities(
        vision: false,
        preserveThinking: false,
        maxContext: 8000,
        supportsToolUse: true,
      );

  @override
  Stream<ThinkingDelta> thinking() async* {
    for (int i = 0; i < chunks.length; i++) {
      yield ThinkingDelta(text: chunks[i], isFinal: i == chunks.length - 1);
    }
  }

  @override
  Future<ModelDecision> decide(
      ConversationSnapshot snapshot, ActionSchema schema) async {
    // Yield enough microtasks for the listener subscribed to `thinking()`
    // to drain its pending deltas before we return the decision.
    for (int i = 0; i < chunks.length + 2; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return decision;
  }
}

class _FakeHost implements LoopHost {
  _FakeHost({required this.tools});

  final List<ToolDescriptor> tools;

  @override
  String get agentsMd => 'AGENTS';

  @override
  String get goal => 'goal';

  @override
  Future<Observation> observe() async => Observation.empty();

  @override
  Future<Map<String, dynamic>> executeAction(
    String tool,
    Map<String, dynamic> args,
  ) async =>
      <String, dynamic>{'ok': true};

  @override
  Future<void> notifyExtensions(
    String tool,
    Map<String, dynamic> args,
    Map<String, dynamic> result,
  ) async {}

  @override
  void disableExtension(String namespace, String reason) {}

  @override
  List<ToolDescriptor> mergedTools() => tools;

  @override
  Set<String> activeExtensionNamespaces() => const <String>{};
}

ToolDescriptor _coreWait() => const ToolDescriptor(
      name: 'core.wait',
      description: 'wait',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    );

Future<TrajectoryWriter> _newWriter(_MemorySink sink) async {
  final w = TrajectoryWriter(sink);
  await w.writeHeader(const SessionHeader(
    goal: 'goal',
    agentsMdHash: 'h',
    buildIdentifier: 'build',
    modelIdentifier: 'fake',
    harnessVersion: '0.1',
    plugins: <ExtensionManifestRecord>[],
    config: <String, dynamic>{},
  ));
  return w;
}

void main() {
  test(
    'driver emits TurnThinking → TurnActionDecided → TurnValidation → '
    'TurnComplete in order',
    () async {
      final sink = _MemorySink();
      final writer = await _newWriter(sink);
      final host = _FakeHost(tools: <ToolDescriptor>[_coreWait()]);
      final provider = _ThinkingProvider(
        chunks: const <String>['plan ', 'next.'],
        decision: const ModelDecision(
          action: (tool: 'core.wait', args: <String, dynamic>{}),
        ),
      );

      final events = <TurnEvent>[];
      final driver = LoopDriver(
        host: host,
        provider: provider,
        conversation: ConversationBuilder(
          systemMessage: '${host.agentsMd}\n\n## Goal\n${host.goal}',
          tools: host.mergedTools(),
        ),
        validator: const ActionValidator(),
        writer: writer,
        onTurnEvent: events.add,
      );

      await driver.runTurn();

      // Allow any pending microtasks (thinking stream cancellation) to flush.
      await Future<void>.delayed(Duration.zero);

      // First the thinking deltas, then the action+validation, then complete.
      final thinkingCount =
          events.whereType<TurnThinking>().length;
      expect(thinkingCount, equals(2));

      // Order check: thinking events all precede the action+validation events
      // (the loop driver awaits decide before emitting them).
      final firstActionIdx = events.indexWhere(
        (e) => e is TurnActionDecided,
      );
      final lastThinkingIdx = events
          .lastIndexWhere((e) => e is TurnThinking);
      expect(lastThinkingIdx, lessThan(firstActionIdx));

      // Sequence after the thinking deltas.
      final tail = events.skip(firstActionIdx).toList();
      expect(tail.map((e) => e.runtimeType.toString()).toList(),
          equals(<String>[
            'TurnActionDecided',
            'TurnValidation',
            'TurnUsage',
            'TurnComplete',
          ]));

      final action = tail[0] as TurnActionDecided;
      expect(action.toolName, equals('core.wait'));
      expect(action.args, isEmpty);

      final validation = tail[1] as TurnValidation;
      expect(validation.ok, isTrue);

      final usage = tail[2] as TurnUsage;
      expect(usage.turn, equals(0));
      expect(usage.estimatedTokens, greaterThan(0));
      expect(usage.trimBudget, equals(32000));

      final complete = tail[3] as TurnComplete;
      expect(complete.turn, equals(0));
    },
  );

  test(
    'thinking subscription is cancelled when decide returns '
    '(no orphan listeners)',
    () async {
      final sink = _MemorySink();
      final writer = await _newWriter(sink);
      final host = _FakeHost(tools: <ToolDescriptor>[_coreWait()]);

      // Provider whose `thinking()` stream stays open indefinitely. If the
      // driver fails to cancel its subscription, additional emissions on
      // a fresh listen() would surface — we verify the StreamController is
      // closeable via a counter-based check on emitted deltas.
      final provider = _ControllableThinkingProvider(
        decision: const ModelDecision(
          action: (tool: 'core.wait', args: <String, dynamic>{}),
        ),
      );

      final events = <TurnEvent>[];
      final driver = LoopDriver(
        host: host,
        provider: provider,
        conversation: ConversationBuilder(
          systemMessage: '${host.agentsMd}\n\n## Goal\n${host.goal}',
          tools: host.mergedTools(),
        ),
        validator: const ActionValidator(),
        writer: writer,
        onTurnEvent: events.add,
      );

      // Pump one delta before decide resolves.
      provider.pushThinking(
        const ThinkingDelta(text: 'a', isFinal: false),
      );
      await driver.runTurn();
      await Future<void>.delayed(Duration.zero);

      // After runTurn returns, push another delta — must not produce a
      // new TurnThinking event because the subscription was cancelled.
      final thinkingBefore = events.whereType<TurnThinking>().length;
      provider.pushThinking(
        const ThinkingDelta(text: 'b', isFinal: false),
      );
      await Future<void>.delayed(Duration.zero);
      final thinkingAfter = events.whereType<TurnThinking>().length;

      expect(thinkingAfter, equals(thinkingBefore));

      await provider.dispose();
    },
  );
}

class _ControllableThinkingProvider extends ModelProvider {
  _ControllableThinkingProvider({required this.decision});

  final ModelDecision decision;
  final StreamController<ThinkingDelta> _ctl =
      StreamController<ThinkingDelta>.broadcast();

  void pushThinking(ThinkingDelta d) => _ctl.add(d);

  Future<void> dispose() => _ctl.close();

  @override
  ModelCapabilities get capabilities => const ModelCapabilities(
        vision: false,
        preserveThinking: false,
        maxContext: 8000,
        supportsToolUse: true,
      );

  @override
  Stream<ThinkingDelta> thinking() => _ctl.stream;

  @override
  Future<ModelDecision> decide(
      ConversationSnapshot snapshot, ActionSchema schema) async {
    // Give the thinking listener a chance to drain pending deltas
    // before decide returns.
    await Future<void>.delayed(Duration.zero);
    return decision;
  }
}
