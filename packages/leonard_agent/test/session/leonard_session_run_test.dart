import 'dart:async';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

class _FakeVm extends VmService {
  _FakeVm() : super(const Stream<dynamic>.empty(), (_) {});

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) async {
    if (method == 'ext.leonard.core.handshake') {
      final r = Response();
      r.json = <String, dynamic>{
        'contractVersion': '1.0',
        'extensions': <Map<String, dynamic>>[],
      };
      return r;
    }
    final r = Response();
    r.json = <String, dynamic>{};
    return r;
  }

  @override
  Future<void> dispose() async {}
}

class _MemorySink extends TrajectorySink {
  final List<String> lines = <String>[];
  @override
  Future<void> writeLine(String line) async => lines.add(line);
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
}

class _StubProvider extends ModelProvider {
  @override
  ModelCapabilities get capabilities => const ModelCapabilities(
    vision: false,
    preserveThinking: false,
    maxContext: 8000,
    supportsToolUse: true,
  );
  @override
  Stream<ThinkingDelta> thinking() => const Stream.empty();
  @override
  Future<ModelDecision> decide(
    ConversationSnapshot snapshot,
    ActionSchema schema,
  ) async {
    return ModelDecision(
      action: (
        tool: 'core.done',
        args: <String, dynamic>{'reason': 'finished'},
      ),
    );
  }
}

class _StubHost implements LoopHost {
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
  ) async => <String, dynamic>{'ok': true};
  @override
  Future<void> notifyExtensions(
    String tool,
    Map<String, dynamic> args,
    Map<String, dynamic> result,
  ) async {}
  @override
  void disableExtension(String namespace, String reason) {}
  @override
  List<ToolDescriptor> mergedTools() => const <ToolDescriptor>[
    ToolDescriptor(
      name: 'core.done',
      description: 'done',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'reason': <String, dynamic>{'type': 'string'},
        },
        'additionalProperties': false,
      },
    ),
  ];
  @override
  Set<String> activeExtensionNamespaces() => const <String>{};
}

class _WaitingProvider extends _StubProvider {
  @override
  Future<ModelDecision> decide(
    ConversationSnapshot snapshot,
    ActionSchema schema,
  ) async =>
      ModelDecision(action: (tool: 'core.wait', args: <String, dynamic>{}));
}

class _WaitingHost extends _StubHost {
  @override
  List<ToolDescriptor> mergedTools() => <ToolDescriptor>[
    ...super.mergedTools(),
    const ToolDescriptor(
      name: 'core.wait',
      description: 'wait',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'additionalProperties': false,
      },
    ),
  ];
}

Future<TrajectoryWriter> _writer([_MemorySink? sink]) async {
  final writer = TrajectoryWriter(sink ?? _MemorySink());
  await writer.writeHeader(
    const SessionHeader(
      goal: 'goal',
      agentsMdHash: 'h',
      buildIdentifier: 'b',
      modelIdentifier: 'fake',
      harnessVersion: '0.1',
      extensions: <ExtensionManifestRecord>[],
      config: <String, dynamic>{},
    ),
  );
  return writer;
}

void main() {
  test(
    'LeonardSession.run() drives a session and returns the termination',
    () async {
      final client = VmServiceClient.forTest(_FakeVm(), 'iso');
      final session = LeonardSession.forTest(client);
      await session.start('goal', const LeonardConfig());

      final sink = _MemorySink();
      final writer = TrajectoryWriter(sink);
      await writer.writeHeader(
        const SessionHeader(
          goal: 'goal',
          agentsMdHash: 'h',
          buildIdentifier: 'b',
          modelIdentifier: 'fake',
          harnessVersion: '0.1',
          extensions: <ExtensionManifestRecord>[],
          config: <String, dynamic>{},
        ),
      );

      final t = await session.run(
        host: _StubHost(),
        provider: _StubProvider(),
        writer: writer,
      );

      expect(t.outcome, SessionOutcome.done);
      expect(t.finalSummary, 'finished');
      await session.end();
    },
  );

  test('LeonardSession.run() before start() throws StateError', () async {
    final client = VmServiceClient.forTest(_FakeVm(), 'iso');
    final session = LeonardSession.forTest(client);
    final sink = _MemorySink();
    final writer = TrajectoryWriter(sink);
    await writer.writeHeader(
      const SessionHeader(
        goal: 'goal',
        agentsMdHash: 'h',
        buildIdentifier: 'b',
        modelIdentifier: 'fake',
        harnessVersion: '0.1',
        extensions: <ExtensionManifestRecord>[],
        config: <String, dynamic>{},
      ),
    );
    expect(
      () => session.run(
        host: _StubHost(),
        provider: _StubProvider(),
        writer: writer,
      ),
      throwsStateError,
    );
  });

  test('run() honors LeonardConfig.sessionBudget from start()', () async {
    final session = LeonardSession.forTest(
      VmServiceClient.forTest(_FakeVm(), 'iso'),
    );
    await session.start(
      'goal',
      const LeonardConfig(sessionBudget: Duration.zero),
    );
    final t = await session.run(
      host: _StubHost(),
      provider: _StubProvider(),
      writer: await _writer(),
    );
    expect(t.outcome, SessionOutcome.budgetExhausted);
    await session.end();
  });

  test('run() honors LeonardConfig.maxTurns from start()', () async {
    final session = LeonardSession.forTest(
      VmServiceClient.forTest(_FakeVm(), 'iso'),
    );
    await session.start('goal', const LeonardConfig(maxTurns: 2));
    final sink = _MemorySink();
    final t = await session.run(
      host: _WaitingHost(),
      provider: _WaitingProvider(),
      writer: await _writer(sink),
    );
    expect(t.outcome, SessionOutcome.budgetExhausted);
    expect(sink.lines.where((l) => l.contains('"type":"turn"')), hasLength(2));
    await session.end();
  });
}
