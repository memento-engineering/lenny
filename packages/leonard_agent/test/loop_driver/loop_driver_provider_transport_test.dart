import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' show ClientException;
import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

class _MemorySink extends TrajectorySink {
  final List<String> lines = <String>[];

  @override
  Future<void> writeLine(String line) async => lines.add(line);

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

/// Fake provider driven by a script: a [ModelDecision] entry is returned, any
/// other entry is THROWN. The last entry repeats once the script runs out.
class _ScriptedProvider extends ModelProvider {
  _ScriptedProvider(this.script);

  final List<Object> script;
  int _i = 0;

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
    final Object next = _i >= script.length ? script.last : script[_i++];
    if (next is ModelDecision) return next;
    throw next;
  }
}

/// An exception class the driver has no classification for.
class _UnknownHarnessFault implements Exception {
  const _UnknownHarnessFault();

  @override
  String toString() => 'unknown harness fault';
}

class _FakeHost implements LoopHost {
  _FakeHost({required this.tools, this.observeFn});

  final List<ToolDescriptor> tools;
  Future<Observation> Function()? observeFn;

  @override
  String get agentsMd => 'AGENTS';

  @override
  String get goal => 'goal';

  @override
  Future<Observation> observe() async =>
      observeFn == null ? Observation.empty() : observeFn!();

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

ToolDescriptor _coreDone() => const ToolDescriptor(
  name: 'core.done',
  description: 'done',
  inputSchema: <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'reason': <String, dynamic>{'type': 'string'},
    },
    'additionalProperties': false,
  },
);

Future<TrajectoryWriter> _newWriter(_MemorySink sink) async {
  final TrajectoryWriter w = TrajectoryWriter(sink);
  await w.writeHeader(
    const SessionHeader(
      goal: 'goal',
      agentsMdHash: 'h',
      buildIdentifier: 'build',
      modelIdentifier: 'fake',
      harnessVersion: '0.1',
      extensions: <ExtensionManifestRecord>[],
      config: <String, dynamic>{},
    ),
  );
  return w;
}

LoopDriver _newDriver({
  required _FakeHost host,
  required _ScriptedProvider provider,
  required TrajectoryWriter writer,
  Duration providerRetryBackoff = Duration.zero,
}) => LoopDriver(
  host: host,
  provider: provider,
  conversation: ConversationBuilder(
    systemMessage: '${host.agentsMd}\n\n## Goal\n${host.goal}',
    tools: host.mergedTools(),
  ),
  validator: const ActionValidator(),
  writer: writer,
  maxTurns: 10,
  providerRetryBackoff: providerRetryBackoff,
);

List<Map<String, dynamic>> _turns(_MemorySink sink) {
  final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
  for (final String line in sink.lines) {
    final Map<String, dynamic> r = (jsonDecode(line) as Map)
        .cast<String, dynamic>();
    if (r['type'] == 'turn') out.add(r);
  }
  return out;
}

Map<String, dynamic> _lastFooter(_MemorySink sink) {
  final Map<String, dynamic> last = (jsonDecode(sink.lines.last) as Map)
      .cast<String, dynamic>();
  expect(last['type'], 'footer');
  return last;
}

ClientException _streamClosed() => ClientException(
  'Connection closed while receiving data, '
  'uri=http://localhost:8080/v1/messages',
);

void main() {
  group('LoopDriver provider transport failures', () {
    test('a ClientException on turn 0 is a provider_transport failed turn and '
        'the session still reaches done on turn 1', () async {
      final _MemorySink sink = _MemorySink();
      final TrajectoryWriter writer = await _newWriter(sink);
      final _FakeHost host = _FakeHost(tools: <ToolDescriptor>[_coreDone()]);
      final _ScriptedProvider provider = _ScriptedProvider(<Object>[
        _streamClosed(),
        ModelDecision(
          action: (tool: 'core.done', args: <String, dynamic>{'reason': 'ok'}),
        ),
      ]);
      final LoopDriver driver = _newDriver(
        host: host,
        provider: provider,
        writer: writer,
      );

      final SessionTermination t = await driver.runSession();

      expect(t.outcome, SessionOutcome.done);
      expect(t.finalSummary, 'ok');
      final List<Map<String, dynamic>> turns = _turns(sink);
      expect(turns, hasLength(2));
      expect(turns[0]['validation']['ok'], isFalse);
      expect(turns[0]['validation']['reason'], 'provider_transport');
      expect(
        turns[0]['validation']['provider_error'],
        contains('ClientException'),
      );
      expect(turns[1]['proposed_action']['tool'], 'core.done');
      expect(_lastFooter(sink)['outcome'], 'done');
    });

    test('three consecutive provider failures → harness_error agent_stuck '
        'with a detail naming ClientException', () async {
      final _MemorySink sink = _MemorySink();
      final TrajectoryWriter writer = await _newWriter(sink);
      final _FakeHost host = _FakeHost(tools: <ToolDescriptor>[_coreWait()]);
      final _ScriptedProvider provider = _ScriptedProvider(<Object>[
        _streamClosed(),
      ]);
      final LoopDriver driver = _newDriver(
        host: host,
        provider: provider,
        writer: writer,
      );

      final SessionTermination t = await driver.runSession();

      expect(t.outcome, SessionOutcome.harnessError);
      expect(t.harnessError, HarnessError.agentStuck);
      expect(t.terminationDetail, contains('ClientException'));
      expect(t.terminationDetail, contains('provider_request_id=none'));
      expect(driver.turnIndex, 3);
      final Map<String, dynamic> footer = _lastFooter(sink);
      expect(footer['harness_error'], 'agent_stuck');
      expect(footer['termination_detail'], contains('ClientException'));
    });

    test(
      'the detail carries the last successful provider_request_id',
      () async {
        final _MemorySink sink = _MemorySink();
        final TrajectoryWriter writer = await _newWriter(sink);
        final _FakeHost host = _FakeHost(tools: <ToolDescriptor>[_coreWait()]);
        final _ScriptedProvider provider = _ScriptedProvider(<Object>[
          ModelDecision(
            action: (tool: 'core.wait', args: <String, dynamic>{}),
            providerRequestId: 'req-7',
          ),
          _streamClosed(),
        ]);
        final LoopDriver driver = _newDriver(
          host: host,
          provider: provider,
          writer: writer,
        );

        final SessionTermination t = await driver.runSession();

        expect(t.harnessError, HarnessError.agentStuck);
        expect(t.terminationDetail, contains('provider_request_id=req-7'));
        expect(driver.turnIndex, 4);
      },
    );

    test('the retry backoff is applied before the next turn', () async {
      final _MemorySink sink = _MemorySink();
      final TrajectoryWriter writer = await _newWriter(sink);
      final _FakeHost host = _FakeHost(tools: <ToolDescriptor>[_coreDone()]);
      final _ScriptedProvider provider = _ScriptedProvider(<Object>[
        _streamClosed(),
        ModelDecision(
          action: (tool: 'core.done', args: <String, dynamic>{'reason': 'ok'}),
        ),
      ]);
      final LoopDriver driver = _newDriver(
        host: host,
        provider: provider,
        writer: writer,
        providerRetryBackoff: const Duration(milliseconds: 40),
      );

      final Stopwatch sw = Stopwatch()..start();
      await driver.runSession();
      sw.stop();

      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(40));
    });

    test('an unclassified exception still writes a classified footer and '
        'still propagates', () async {
      final _MemorySink sink = _MemorySink();
      final TrajectoryWriter writer = await _newWriter(sink);
      final _FakeHost host = _FakeHost(
        tools: <ToolDescriptor>[_coreWait()],
        observeFn: () async => throw const _UnknownHarnessFault(),
      );
      final _ScriptedProvider provider = _ScriptedProvider(<Object>[
        ModelDecision(action: (tool: 'core.wait', args: <String, dynamic>{})),
      ]);
      final LoopDriver driver = _newDriver(
        host: host,
        provider: provider,
        writer: writer,
      );

      await expectLater(
        driver.runSession(),
        throwsA(isA<_UnknownHarnessFault>()),
      );

      final Map<String, dynamic> footer = _lastFooter(sink);
      expect(footer['outcome'], 'harness_error');
      expect(footer['harness_error'], 'unclassified');
      expect(
        footer['termination_detail'] as String,
        contains('_UnknownHarnessFault'),
      );
      expect(footer['termination_detail'] as String, isNotEmpty);
    });
  });
}
