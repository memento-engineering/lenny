import 'dart:async';
import 'dart:convert';

import 'package:exploration_agent/exploration_agent.dart';
import 'package:test/test.dart';

// =====================================================================
// Test fakes (shared shape with loop_driver_turn_test.dart but kept
// independent so the suites can run in parallel).
// =====================================================================

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

class _FakeProvider extends ModelProvider {
  _FakeProvider({required this.script});

  final List<ModelDecision> script;
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
  Future<ModelDecision> decide(PromptPayload prompt, ActionSchema schema) async {
    if (_i >= script.length) {
      // Loop the last decision so callers don't need to pad with extras.
      return script.last;
    }
    return script[_i++];
  }
}

class _FakeHost implements LoopHost {
  _FakeHost({
    required this.tools,
    this.observeFn,
  });

  final List<ToolDescriptor> tools;
  Future<Observation> Function()? observeFn;
  Set<String> _activeNamespaces = <String>{};
  final Set<String> _disabled = <String>{};

  void setActiveNamespaces(Set<String> ns) {
    _activeNamespaces = ns;
  }

  @override
  String get agentsMd => 'AGENTS';

  @override
  String get goal => 'goal';

  @override
  Future<Observation> observe() async {
    if (observeFn != null) return observeFn!();
    return Observation.empty();
  }

  @override
  Future<Map<String, dynamic>> executeAction(
    String tool,
    Map<String, dynamic> args,
  ) async {
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<void> notifyPlugins(
    String tool,
    Map<String, dynamic> args,
    Map<String, dynamic> result,
  ) async {}

  @override
  void disablePlugin(String namespace, String reason) {
    _disabled.add(namespace);
    _activeNamespaces = _activeNamespaces.where((n) => n != namespace).toSet();
  }

  @override
  List<ToolDescriptor> mergedTools() => tools.where((t) {
        final dot = t.name.indexOf('.');
        if (dot < 0) return true;
        final ns = t.name.substring(0, dot);
        return !_disabled.contains(ns);
      }).toList();

  @override
  Set<String> activePluginNamespaces() => _activeNamespaces;

  Set<String> get disabledPlugins => _disabled;
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
  final w = TrajectoryWriter(sink);
  await w.writeHeader(const SessionHeader(
    goal: 'goal',
    agentsMdHash: 'h',
    buildIdentifier: 'build',
    modelIdentifier: 'fake',
    harnessVersion: '0.1',
    plugins: <PluginManifestRecord>[],
    config: <String, dynamic>{},
  ));
  return w;
}

class _FakeClock {
  _FakeClock(this._now);
  DateTime _now;
  DateTime call() => _now;
  void advance(Duration d) => _now = _now.add(d);
}

LoopDriver _newDriver({
  required _FakeHost host,
  required _FakeProvider provider,
  required TrajectoryWriter writer,
  Duration turnBudget = const Duration(seconds: 30),
  Duration sessionBudget = const Duration(minutes: 15),
  int maxTurns = 50,
  DateTime Function()? clock,
}) {
  return LoopDriver(
    host: host,
    provider: provider,
    assembler: const PromptAssembler(),
    validator: const ActionValidator(),
    writer: writer,
    summary: RunningSummary(counter: WhitespaceTokenCounter()),
    actions: ActionRing(),
    turnBudget: turnBudget,
    sessionBudget: sessionBudget,
    maxTurns: maxTurns,
    clock: clock,
  );
}

Map<String, dynamic> _lastFooter(_MemorySink sink) {
  final last = jsonDecode(sink.lines.last);
  expect((last as Map)['type'], 'footer',
      reason: 'expected last record to be a footer');
  return last.cast<String, dynamic>();
}

void main() {
  group('LoopDriver.runSession', () {
    test('maxTurns terminates with budget_exhausted', () async {
      final sink = _MemorySink();
      final writer = await _newWriter(sink);
      final host = _FakeHost(tools: <ToolDescriptor>[_coreWait()]);
      final provider = _FakeProvider(script: <ModelDecision>[
        ModelDecision(action: (tool: 'core.wait', args: <String, dynamic>{})),
      ]);
      final driver = _newDriver(
        host: host,
        provider: provider,
        writer: writer,
        maxTurns: 5,
      );
      final t = await driver.runSession();
      expect(t.outcome, SessionOutcome.budgetExhausted);
      expect(driver.turnIndex, 5);
      final footer = _lastFooter(sink);
      expect(footer['outcome'], 'budget_exhausted');
      expect(footer['total_turns'], 5);
    });

    test('15-min wall-clock terminates with budget_exhausted', () async {
      final sink = _MemorySink();
      final writer = await _newWriter(sink);
      final clock = _FakeClock(DateTime(2026, 1, 1, 12, 0, 0));
      final host = _FakeHost(
        tools: <ToolDescriptor>[_coreWait()],
        observeFn: () async {
          // Advance the clock by 1 minute on each turn.
          clock.advance(const Duration(minutes: 1));
          return Observation.empty();
        },
      );
      final provider = _FakeProvider(script: <ModelDecision>[
        ModelDecision(action: (tool: 'core.wait', args: <String, dynamic>{})),
      ]);
      final driver = _newDriver(
        host: host,
        provider: provider,
        writer: writer,
        sessionBudget: const Duration(minutes: 15),
        maxTurns: 100, // not the binding budget
        clock: clock.call,
      );
      final t = await driver.runSession();
      expect(t.outcome, SessionOutcome.budgetExhausted);
      // 15 turns means 15 minutes elapsed in fake clock.
      expect(driver.turnIndex, lessThanOrEqualTo(15));
      final footer = _lastFooter(sink);
      expect(footer['outcome'], 'budget_exhausted');
    });

    test('three failed turns → harness_error agent_stuck', () async {
      final sink = _MemorySink();
      final writer = await _newWriter(sink);
      final host = _FakeHost(tools: <ToolDescriptor>[_coreWait()]);
      // Always propose an unknown tool — validator will reject every time
      // until the budget is exhausted, producing a failed turn.
      final provider = _FakeProvider(script: <ModelDecision>[
        ModelDecision(action: (tool: 'bogus.x', args: <String, dynamic>{})),
      ]);
      final driver = _newDriver(host: host, provider: provider, writer: writer);
      final t = await driver.runSession();
      expect(t.outcome, SessionOutcome.harnessError);
      expect(t.harnessError, HarnessError.agentStuck);
      // Exactly 3 failed turns occurred before termination.
      expect(driver.turnIndex, 3);
      final footer = _lastFooter(sink);
      expect(footer['outcome'], 'harness_error');
      expect(footer['harness_error'], 'agent_stuck');
    });

    test('connection lost mid-turn → harness_error connection_lost; '
        'footer present', () async {
      final sink = _MemorySink();
      final writer = await _newWriter(sink);
      final host = _FakeHost(
        tools: <ToolDescriptor>[_coreWait()],
        observeFn: () async {
          throw const VmServiceConnectionLost();
        },
      );
      final provider = _FakeProvider(script: <ModelDecision>[
        ModelDecision(action: (tool: 'core.wait', args: <String, dynamic>{})),
      ]);
      final driver = _newDriver(host: host, provider: provider, writer: writer);
      final t = await driver.runSession();
      expect(t.outcome, SessionOutcome.harnessError);
      expect(t.harnessError, HarnessError.connectionLost);
      final footer = _lastFooter(sink);
      expect(footer['outcome'], 'harness_error');
      expect(footer['harness_error'], 'connection_lost');
    });

    test('core.done(reason) → outcome=done, footer.final_summary==reason',
        () async {
      final sink = _MemorySink();
      final writer = await _newWriter(sink);
      final host = _FakeHost(tools: <ToolDescriptor>[_coreDone()]);
      final provider = _FakeProvider(script: <ModelDecision>[
        ModelDecision(
          action: (tool: 'core.done', args: <String, dynamic>{
            'reason': 'login complete',
          }),
        ),
      ]);
      final driver = _newDriver(host: host, provider: provider, writer: writer);
      final t = await driver.runSession();
      expect(t.outcome, SessionOutcome.done);
      expect(t.finalSummary, 'login complete');
      final footer = _lastFooter(sink);
      expect(footer['outcome'], 'done');
      expect(footer['final_summary'], 'login complete');
    });

    test('plugin auto-disable does NOT terminate session', () async {
      final sink = _MemorySink();
      final writer = await _newWriter(sink);
      // For 3 turns: router fragment carries an error. After that the
      // plugin is disabled; subsequent observations are clean.
      int turn = 0;
      final host = _FakeHost(
        tools: <ToolDescriptor>[_coreWait()],
        observeFn: () async {
          turn++;
          if (turn <= 3) {
            return Observation(
              core: CoreFragment.empty,
              plugins: <String, PluginFragment>{
                'router': PluginFragment(
                  namespace: 'router',
                  data: <String, dynamic>{'error': 'boom'},
                  deltaFriendly: false,
                ),
              },
              stability: StabilityMetadata.empty,
            );
          }
          return Observation.empty();
        },
      );
      host.setActiveNamespaces(<String>{'router'});
      final provider = _FakeProvider(script: <ModelDecision>[
        ModelDecision(action: (tool: 'core.wait', args: <String, dynamic>{})),
      ]);
      final driver = _newDriver(
        host: host,
        provider: provider,
        writer: writer,
        maxTurns: 8,
      );
      final t = await driver.runSession();
      expect(t.outcome, SessionOutcome.budgetExhausted);
      expect(host.disabledPlugins, contains('router'));
      // We continued running for 5 more turns after auto-disable on turn 2
      // (third strike-bearing turn, idx=2).
      expect(driver.turnIndex, 8);
    });

    test('consecutive-failed-turns counter resets on a successful turn',
        () async {
      final sink = _MemorySink();
      final writer = await _newWriter(sink);
      final host = _FakeHost(tools: <ToolDescriptor>[_coreWait()]);
      // Pattern: fail, fail, ok, fail, fail, ok — never reaches 3 in a row.
      final provider = _FakeProvider(script: <ModelDecision>[
        ModelDecision(action: (tool: 'bogus.x', args: <String, dynamic>{})),
        ModelDecision(action: (tool: 'bogus.x', args: <String, dynamic>{})),
        ModelDecision(action: (tool: 'core.wait', args: <String, dynamic>{})),
        ModelDecision(action: (tool: 'bogus.x', args: <String, dynamic>{})),
        ModelDecision(action: (tool: 'bogus.x', args: <String, dynamic>{})),
        ModelDecision(action: (tool: 'core.wait', args: <String, dynamic>{})),
      ]);
      final driver = _newDriver(
        host: host,
        provider: provider,
        writer: writer,
        maxTurns: 6,
      );
      final t = await driver.runSession();
      // 6 turns ran; budget exhausted, NOT agent_stuck.
      expect(t.outcome, SessionOutcome.budgetExhausted);
      expect(driver.turnIndex, 6);
    });
  });
}
