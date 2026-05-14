import 'dart:async';

import 'package:exploration_agent/exploration_agent.dart';
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
    if (method == 'ext.flutter.exploration.core.handshake') {
      final r = Response();
      r.json = <String, dynamic>{
        'contractVersion': '1.0',
        'plugins': <Map<String, dynamic>>[],
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
  Future<ModelDecision> decide(PromptPayload prompt, ActionSchema schema) async {
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
  ) async =>
      <String, dynamic>{'ok': true};
  @override
  Future<void> notifyPlugins(
    String tool,
    Map<String, dynamic> args,
    Map<String, dynamic> result,
  ) async {}
  @override
  void disablePlugin(String namespace, String reason) {}
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
  Set<String> activePluginNamespaces() => const <String>{};
}

void main() {
  test(
      'ExplorationSession.run() drives a session and returns the termination',
      () async {
    final client = VmServiceClient.forTest(_FakeVm(), 'iso');
    final session = ExplorationSession.forTest(client);
    await session.start('goal', const ExplorationConfig());

    final sink = _MemorySink();
    final writer = TrajectoryWriter(sink);
    await writer.writeHeader(const SessionHeader(
      goal: 'goal',
      agentsMdHash: 'h',
      buildIdentifier: 'b',
      modelIdentifier: 'fake',
      harnessVersion: '0.1',
      plugins: <PluginManifestRecord>[],
      config: <String, dynamic>{},
    ));

    final t = await session.run(
      host: _StubHost(),
      provider: _StubProvider(),
      writer: writer,
    );

    expect(t.outcome, SessionOutcome.done);
    expect(t.finalSummary, 'finished');
    await session.end();
  });

  test('ExplorationSession.run() before start() throws StateError', () async {
    final client = VmServiceClient.forTest(_FakeVm(), 'iso');
    final session = ExplorationSession.forTest(client);
    final sink = _MemorySink();
    final writer = TrajectoryWriter(sink);
    await writer.writeHeader(const SessionHeader(
      goal: 'goal',
      agentsMdHash: 'h',
      buildIdentifier: 'b',
      modelIdentifier: 'fake',
      harnessVersion: '0.1',
      plugins: <PluginManifestRecord>[],
      config: <String, dynamic>{},
    ));
    expect(
      () => session.run(
        host: _StubHost(),
        provider: _StubProvider(),
        writer: writer,
      ),
      throwsStateError,
    );
  });
}
