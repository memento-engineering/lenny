import 'dart:async';
import 'dart:convert';

import 'package:leonard_agent/leonard_agent.dart';
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
  Future<ModelDecision> decide(
    ConversationSnapshot snapshot,
    ActionSchema schema,
  ) async {
    if (_i >= script.length) {
      // Loop the last decision so callers don't need to pad with extras.
      return script.last;
    }
    return script[_i++];
  }
}

class _FakeHost implements LoopHost {
  _FakeHost({required this.tools, this.observeFn});

  final List<ToolDescriptor> tools;
  Future<Observation> Function()? observeFn;
  Future<Map<String, dynamic>> Function(String tool, Map<String, dynamic> args)?
  executeFn;
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
    if (executeFn != null) return executeFn!(tool, args);
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<void> notifyExtensions(
    String tool,
    Map<String, dynamic> args,
    Map<String, dynamic> result,
  ) async {}

  @override
  void disableExtension(String namespace, String reason) {
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
  Set<String> activeExtensionNamespaces() => _activeNamespaces;

  Set<String> get disabledExtensions => _disabled;
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
    conversation: ConversationBuilder(
      systemMessage: '${host.agentsMd}\n\n## Goal\n${host.goal}',
      tools: host.mergedTools(),
    ),
    validator: const ActionValidator(),
    writer: writer,
    turnBudget: turnBudget,
    sessionBudget: sessionBudget,
    maxTurns: maxTurns,
    clock: clock,
  );
}

Map<String, dynamic> _lastFooter(_MemorySink sink) {
  final last = jsonDecode(sink.lines.last);
  expect(
    (last as Map)['type'],
    'footer',
    reason: 'expected last record to be a footer',
  );
  return last.cast<String, dynamic>();
}

void main() {
  group('LoopDriver.runSession', () {
    test('maxTurns terminates with budget_exhausted', () async {
      final sink = _MemorySink();
      final writer = await _newWriter(sink);
      final host = _FakeHost(tools: <ToolDescriptor>[_coreWait()]);
      final provider = _FakeProvider(
        script: <ModelDecision>[
          ModelDecision(action: (tool: 'core.wait', args: <String, dynamic>{})),
        ],
      );
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
      final provider = _FakeProvider(
        script: <ModelDecision>[
          ModelDecision(action: (tool: 'core.wait', args: <String, dynamic>{})),
        ],
      );
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
      final provider = _FakeProvider(
        script: <ModelDecision>[
          ModelDecision(action: (tool: 'bogus.x', args: <String, dynamic>{})),
        ],
      );
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
      final provider = _FakeProvider(
        script: <ModelDecision>[
          ModelDecision(action: (tool: 'core.wait', args: <String, dynamic>{})),
        ],
      );
      final driver = _newDriver(host: host, provider: provider, writer: writer);
      final t = await driver.runSession();
      expect(t.outcome, SessionOutcome.harnessError);
      expect(t.harnessError, HarnessError.connectionLost);
      final footer = _lastFooter(sink);
      expect(footer['outcome'], 'harness_error');
      expect(footer['harness_error'], 'connection_lost');
    });

    test(
      'core.done(reason) → outcome=done, footer.final_summary==reason',
      () async {
        final sink = _MemorySink();
        final writer = await _newWriter(sink);
        final host = _FakeHost(tools: <ToolDescriptor>[_coreDone()]);
        final provider = _FakeProvider(
          script: <ModelDecision>[
            ModelDecision(
              action: (
                tool: 'core.done',
                args: <String, dynamic>{'reason': 'login complete'},
              ),
            ),
          ],
        );
        final driver = _newDriver(
          host: host,
          provider: provider,
          writer: writer,
        );
        final t = await driver.runSession();
        expect(t.outcome, SessionOutcome.done);
        // SessionTermination.finalSummary still captures the core.done
        // reason on the structured return value (the chat-shape rebuild keeps
        // the field on the termination type; only the trajectory footer JSON
        // drops the final_summary key in v2).
        expect(t.finalSummary, 'login complete');
        final footer = _lastFooter(sink);
        expect(footer['outcome'], 'done');
        // v2: final_summary key removed from footer JSON.
        expect(footer.containsKey('final_summary'), isFalse);
      },
    );

    test('extension auto-disable does NOT terminate session', () async {
      final sink = _MemorySink();
      final writer = await _newWriter(sink);
      // For 3 turns: router fragment carries an error. After that the
      // extension is disabled; subsequent observations are clean.
      int turn = 0;
      final host = _FakeHost(
        tools: <ToolDescriptor>[_coreWait()],
        observeFn: () async {
          turn++;
          if (turn <= 3) {
            return Observation(
              core: CoreFragment.empty,
              extensions: <String, ExtensionFragment>{
                'router': ExtensionFragment(
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
      final provider = _FakeProvider(
        script: <ModelDecision>[
          ModelDecision(action: (tool: 'core.wait', args: <String, dynamic>{})),
        ],
      );
      final driver = _newDriver(
        host: host,
        provider: provider,
        writer: writer,
        maxTurns: 8,
      );
      final t = await driver.runSession();
      expect(t.outcome, SessionOutcome.budgetExhausted);
      expect(host.disabledExtensions, contains('router'));
      // We continued running for 5 more turns after auto-disable on turn 2
      // (third strike-bearing turn, idx=2).
      expect(driver.turnIndex, 8);
    });

    test(
      'consecutive-failed-turns counter resets on a successful turn',
      () async {
        final sink = _MemorySink();
        final writer = await _newWriter(sink);
        final host = _FakeHost(tools: <ToolDescriptor>[_coreWait()]);
        // Pattern: fail, fail, ok, fail, fail, ok — never reaches 3 in a row.
        final provider = _FakeProvider(
          script: <ModelDecision>[
            ModelDecision(action: (tool: 'bogus.x', args: <String, dynamic>{})),
            ModelDecision(action: (tool: 'bogus.x', args: <String, dynamic>{})),
            ModelDecision(
              action: (tool: 'core.wait', args: <String, dynamic>{}),
            ),
            ModelDecision(action: (tool: 'bogus.x', args: <String, dynamic>{})),
            ModelDecision(action: (tool: 'bogus.x', args: <String, dynamic>{})),
            ModelDecision(
              action: (tool: 'core.wait', args: <String, dynamic>{}),
            ),
          ],
        );
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
      },
    );

    test(
      '5 consecutive turn_timeouts → budget_exhausted + termination_detail=inference_latency',
      () async {
        final sink = _MemorySink();
        final writer = await _newWriter(sink);
        final host = _FakeHost(
          tools: <ToolDescriptor>[_coreWait()],
          observeFn: () async => Observation.empty(),
        );
        // executeAction never completes → budget fires every turn.
        host.executeFn = (tool, args) =>
            Completer<Map<String, dynamic>>().future;
        final provider = _FakeProvider(
          script: <ModelDecision>[
            ModelDecision(
              action: (tool: 'core.wait', args: <String, dynamic>{}),
            ),
          ],
        );
        final driver = _newDriver(
          host: host,
          provider: provider,
          writer: writer,
          turnBudget: const Duration(milliseconds: 50),
        );
        final t = await driver.runSession();
        expect(t.outcome, SessionOutcome.budgetExhausted);
        expect(t.terminationDetail, 'inference_latency');
        expect(driver.turnIndex, 5);
        expect(driver.consecutiveFailedTurns, 0);
        final footer = _lastFooter(sink);
        expect(footer['outcome'], 'budget_exhausted');
        expect(footer['termination_detail'], 'inference_latency');
      },
    );

    test(
      'turn_timeout→turn_timeout→success resets both counters; no premature termination',
      () async {
        final sink = _MemorySink();
        final writer = await _newWriter(sink);
        int turnCall = 0;
        final host = _FakeHost(
          tools: <ToolDescriptor>[_coreWait()],
          observeFn: () async => Observation.empty(),
        );
        host.executeFn = (tool, args) async {
          turnCall++;
          if (turnCall <= 2) {
            // Delay past the 50ms budget so the turn times out.
            await Future<void>.delayed(const Duration(seconds: 10));
          }
          return <String, dynamic>{'ok': true};
        };
        final provider = _FakeProvider(
          script: <ModelDecision>[
            ModelDecision(
              action: (tool: 'core.wait', args: <String, dynamic>{}),
            ),
          ],
        );
        final driver = _newDriver(
          host: host,
          provider: provider,
          writer: writer,
          turnBudget: const Duration(milliseconds: 50),
          maxTurns: 4,
        );
        final t = await driver.runSession();
        // After 2 timeouts + 1 success, consecutiveTurnTimeouts is reset.
        // Session runs to maxTurns (4), not terminated early by the threshold.
        expect(t.outcome, SessionOutcome.budgetExhausted);
        expect(t.terminationDetail, isNull);
        expect(driver.consecutiveTurnTimeouts, 0);
        expect(driver.consecutiveFailedTurns, 0);
      },
    );
  });
}
