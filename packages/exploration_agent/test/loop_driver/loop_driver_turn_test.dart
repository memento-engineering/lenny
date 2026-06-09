import 'dart:async';
import 'dart:convert';

import 'package:exploration_agent/exploration_agent.dart';
import 'package:test/test.dart';

// =====================================================================
// Test fakes
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
  final List<String> calls = <String>[];

  /// Snapshots passed to [decide], in order. Tests assert on these to
  /// verify the loop driver's conversation-builder bookkeeping (e.g.
  /// failed-action toolResult carry-forward).
  final List<ConversationSnapshot> seenSnapshots = <ConversationSnapshot>[];

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
      ConversationSnapshot snapshot, ActionSchema schema) async {
    calls.add('decide');
    seenSnapshots.add(snapshot);
    if (_i >= script.length) {
      throw StateError('no more scripted decisions');
    }
    return script[_i++];
  }
}

class _FakeHost implements LoopHost {
  _FakeHost({
    required this.observations,
    required this.tools,
    this.executeFn,
  });

  /// Observations to return on each [observe] call (consumed in order).
  final List<Observation> observations;
  int _obsI = 0;

  /// Tools list (constant unless mutated by disablePlugin).
  final List<ToolDescriptor> tools;
  final Set<String> _disabled = <String>{};
  Set<String> _activeNamespaces = <String>{};

  Future<Map<String, dynamic>> Function(String tool, Map<String, dynamic> args)?
      executeFn;

  /// Recorded calls in order. Each entry is `(call, args)`.
  final List<String> calls = <String>[];

  void setActiveNamespaces(Set<String> ns) {
    _activeNamespaces = ns;
  }

  @override
  String get agentsMd => 'AGENTS';

  @override
  String get goal => 'goal';

  @override
  Future<Observation> observe() async {
    calls.add('observe');
    if (_obsI >= observations.length) {
      // Reuse last observation if scripts run dry.
      return observations.last;
    }
    return observations[_obsI++];
  }

  @override
  Future<Map<String, dynamic>> executeAction(
    String tool,
    Map<String, dynamic> args,
  ) async {
    calls.add('executeAction:$tool');
    if (executeFn != null) return executeFn!(tool, args);
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<void> notifyPlugins(
    String tool,
    Map<String, dynamic> args,
    Map<String, dynamic> result,
  ) async {
    calls.add('notifyPlugins:$tool');
  }

  @override
  void disablePlugin(String namespace, String reason) {
    calls.add('disablePlugin:$namespace');
    _disabled.add(namespace);
    _activeNamespaces = _activeNamespaces.where((n) => n != namespace).toSet();
  }

  @override
  List<ToolDescriptor> mergedTools() {
    calls.add('mergedTools');
    return tools.where((t) {
      // Filter out tools belonging to disabled namespaces.
      final dot = t.name.indexOf('.');
      if (dot < 0) return true;
      final ns = t.name.substring(0, dot);
      return !_disabled.contains(ns);
    }).toList();
  }

  @override
  Set<String> activePluginNamespaces() {
    calls.add('activePluginNamespaces');
    return _activeNamespaces;
  }

  Set<String> get disabledPlugins => _disabled;
}

// =====================================================================
// Helpers
// =====================================================================

ToolDescriptor _coreDone() => const ToolDescriptor(
      name: 'core.done',
      description: 'declare done',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'reason': <String, dynamic>{'type': 'string'},
        },
        'additionalProperties': false,
      },
    );

ToolDescriptor _coreWait() => const ToolDescriptor(
      name: 'core.wait',
      description: 'wait',
      inputSchema: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    );

LoopDriver _newDriver({
  required _FakeHost host,
  required _FakeProvider provider,
  required TrajectoryWriter writer,
  Duration turnBudget = const Duration(seconds: 30),
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
  );
}

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

Observation _emptyObs() => Observation.empty();

Observation _obsWithStability(String terminatedBy) => Observation(
      core: CoreFragment.empty,
      plugins: const <String, PluginFragment>{},
      stability: StabilityMetadata(
        policy: 'action_relative',
        terminatedBy: terminatedBy,
        durationMs: 0,
        frameworkBusy: const <String, dynamic>{},
        pluginsBusy: const <PluginBusy>[],
      ),
    );

Observation _obsWithPlugins(Map<String, Map<String, dynamic>> frags) =>
    Observation(
      core: CoreFragment.empty,
      plugins: <String, PluginFragment>{
        for (final e in frags.entries)
          e.key: PluginFragment(
            namespace: e.key,
            data: Map<String, dynamic>.unmodifiable(e.value),
            deltaFriendly: false,
          ),
      },
      stability: StabilityMetadata.empty,
    );

// =====================================================================
// Tests
// =====================================================================

void main() {
  group('LoopDriver.runTurn', () {
    test('happy path: 10 steps execute in order', () async {
      final sink = _MemorySink();
      final writer = await _newWriter(sink);
      final host = _FakeHost(
        observations: <Observation>[_emptyObs()],
        tools: <ToolDescriptor>[_coreDone(), _coreWait()],
      );
      final provider = _FakeProvider(script: <ModelDecision>[
        ModelDecision(
          action: (tool: 'core.wait', args: <String, dynamic>{}),
        ),
      ]);
      final driver = _newDriver(host: host, provider: provider, writer: writer);

      final r = await driver.runTurn();
      expect(r.index, 0);

      // Observable call sequence: observe → activePluginNamespaces (during
      // strike accounting; called at least once) → mergedTools (prompt) →
      // decide → executeAction → notifyPlugins. The exact order is the
      // load-bearing part.
      final calls = host.calls;
      // Drop bookkeeping calls (activePluginNamespaces) for ordering check.
      // Also drop the one-shot mergedTools() call from driver construction
      // (the conversation builder needs the tool list to compose the
      // system message); the per-turn mergedTools() inside runTurn is
      // what the test asserts is still load-bearing.
      final firstMergedToolsConsumed = calls.indexOf('mergedTools');
      final ordered = calls
          .asMap()
          .entries
          .where((e) {
            if (e.key == firstMergedToolsConsumed) return false;
            final c = e.value;
            return c == 'observe' ||
                c == 'mergedTools' ||
                c.startsWith('executeAction') ||
                c.startsWith('notifyPlugins');
          })
          .map((e) => e.value)
          .toList();
      expect(
        ordered,
        equals(<String>[
          'observe',
          'mergedTools',
          'executeAction:core.wait',
          'notifyPlugins:core.wait',
        ]),
      );
      expect(provider.calls, equals(<String>['decide']));

      // The persisted turn record is the last line in the sink (the
      // header was written first).
      expect(sink.lines.length, 2); // header + turn
      final last = jsonDecode(sink.lines.last) as Map<String, dynamic>;
      expect(last['type'], 'turn');
      expect(last['index'], 0);
      expect(last['validation']['ok'], isTrue);
    });

    test('failed action: error carries forward as toolResult on next turn (lenny-jfh / lenny-wisp-cl4)',
        () async {
      final sink = _MemorySink();
      final writer = await _newWriter(sink);
      final host = _FakeHost(
        observations: <Observation>[_emptyObs(), _emptyObs()],
        tools: <ToolDescriptor>[_coreDone(), _coreWait()],
        executeFn: (tool, args) async => <String, dynamic>{
          'ok': false,
          'error': 'provider_id (string) required',
        },
      );
      final provider = _FakeProvider(script: <ModelDecision>[
        ModelDecision(
          action: (tool: 'core.wait', args: <String, dynamic>{}),
        ),
        ModelDecision(
          action: (tool: 'core.wait', args: <String, dynamic>{}),
        ),
      ]);
      final driver = _newDriver(host: host, provider: provider, writer: writer);

      await driver.runTurn(); // turn 0 — fails
      await driver.runTurn(); // turn 1 — picks up the carry-forward

      // The second turn's snapshot starts with the turn-1 UserTurn,
      // which should carry the previous turn's failure as toolResult.
      // (Turn 0's snapshot has a single UserTurn with no toolResult;
      // turn 1's snapshot has 3 turns: UserTurn(turn 0, no toolResult)
      // + AssistantTurn(turn 0) + UserTurn(turn 1, toolResult set).)
      expect(provider.seenSnapshots, hasLength(2));
      final ConversationSnapshot second = provider.seenSnapshots[1];
      final UserTurn carryUserTurn = second.turns.last as UserTurn;
      expect(carryUserTurn.toolResult, isNotNull);
      expect(
        carryUserTurn.toolResult!['error'],
        'provider_id (string) required',
        reason: 'a bare "failed" with no reason leaves the model unable to '
            'self-correct; the error must reach the next turn',
      );
    });

    test('stability budget expired is captured, not failed', () async {
      final sink = _MemorySink();
      final writer = await _newWriter(sink);
      final host = _FakeHost(
        observations: <Observation>[_obsWithStability('budget')],
        tools: <ToolDescriptor>[_coreWait()],
      );
      final provider = _FakeProvider(script: <ModelDecision>[
        ModelDecision(
          action: (tool: 'core.wait', args: <String, dynamic>{}),
        ),
      ]);
      final driver = _newDriver(host: host, provider: provider, writer: writer);
      await driver.runTurn();
      expect(driver.consecutiveFailedTurns, 0);
      // The persisted turn record carries the 'budget' marker in stability.
      final last = jsonDecode(sink.lines.last) as Map<String, dynamic>;
      expect(last['stability']['terminated_by'], 'budget');
    });

    test('turn timeout fires when act takes >budget', () async {
      final sink = _MemorySink();
      final writer = await _newWriter(sink);
      final host = _FakeHost(
        observations: <Observation>[_emptyObs()],
        tools: <ToolDescriptor>[_coreWait()],
        // executeAction never completes within the budget.
        executeFn: (tool, args) => Completer<Map<String, dynamic>>().future,
      );
      final provider = _FakeProvider(script: <ModelDecision>[
        ModelDecision(
          action: (tool: 'core.wait', args: <String, dynamic>{}),
        ),
      ]);
      final driver = _newDriver(
        host: host,
        provider: provider,
        writer: writer,
        turnBudget: const Duration(milliseconds: 50),
      );
      try {
        await driver.runTurn();
        fail('expected TurnFailure');
      } on TurnFailure catch (e) {
        expect(e.reason, 'turn_timeout');
      }
      expect(driver.consecutiveTurnTimeouts, 1);
      expect(driver.consecutiveFailedTurns, 0);
      // The failed-turn record was awaited before the throw — i.e. the
      // last sink line is a turn record with validation.ok=false.
      final last = jsonDecode(sink.lines.last) as Map<String, dynamic>;
      expect(last['type'], 'turn');
      expect(last['validation']['ok'], isFalse);
      expect(last['validation']['reason'], 'turn_timeout');
    });

    test('turn_timeout increments consecutiveTurnTimeouts only, not consecutiveFailedTurns',
        () async {
      final sink = _MemorySink();
      final writer = await _newWriter(sink);
      final host = _FakeHost(
        observations: <Observation>[_emptyObs()],
        tools: <ToolDescriptor>[_coreWait()],
        executeFn: (tool, args) => Completer<Map<String, dynamic>>().future,
      );
      final provider = _FakeProvider(script: <ModelDecision>[
        ModelDecision(action: (tool: 'core.wait', args: <String, dynamic>{})),
      ]);
      final driver = _newDriver(
        host: host,
        provider: provider,
        writer: writer,
        turnBudget: const Duration(milliseconds: 50),
      );
      try {
        await driver.runTurn();
        fail('expected TurnFailure');
      } on TurnFailure catch (e) {
        expect(e.reason, 'turn_timeout');
      }
      expect(driver.consecutiveTurnTimeouts, 1);
      expect(driver.consecutiveFailedTurns, 0);
    });

    test('core.done sets done state and writes turn normally', () async {
      final sink = _MemorySink();
      final writer = await _newWriter(sink);
      final host = _FakeHost(
        observations: <Observation>[_emptyObs()],
        tools: <ToolDescriptor>[_coreDone(), _coreWait()],
      );
      final provider = _FakeProvider(script: <ModelDecision>[
        ModelDecision(
          action: (tool: 'core.done', args: <String, dynamic>{
            'reason': 'reached login',
          }),
        ),
      ]);
      final driver = _newDriver(host: host, provider: provider, writer: writer);
      await driver.runTurn();
      expect(driver.doneRequested, isTrue);
      expect(driver.doneReason, 'reached login');
    });

    test('plugin observation error increments tracker; no auto-disable yet',
        () async {
      final sink = _MemorySink();
      final writer = await _newWriter(sink);
      final host = _FakeHost(
        observations: <Observation>[
          _obsWithPlugins(<String, Map<String, dynamic>>{
            'router': <String, dynamic>{'error': 'boom'},
          }),
        ],
        tools: <ToolDescriptor>[_coreWait()],
      );
      host.setActiveNamespaces(<String>{'router'});
      final provider = _FakeProvider(script: <ModelDecision>[
        ModelDecision(
          action: (tool: 'core.wait', args: <String, dynamic>{}),
        ),
      ]);
      final driver = _newDriver(host: host, provider: provider, writer: writer);
      await driver.runTurn();
      expect(driver.pluginFailures.failuresFor('router'), 1);
      expect(host.disabledPlugins, isEmpty);
    });

    test('three plugin observation errors auto-disable that plugin',
        () async {
      final sink = _MemorySink();
      final writer = await _newWriter(sink);
      final tools = <ToolDescriptor>[
        _coreWait(),
        const ToolDescriptor(
          name: 'router.go',
          description: 'navigate',
          inputSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{},
            'additionalProperties': false,
          },
        ),
      ];
      final host = _FakeHost(
        observations: <Observation>[
          _obsWithPlugins(<String, Map<String, dynamic>>{
            'router': <String, dynamic>{'error': 'boom'},
          }),
          _obsWithPlugins(<String, Map<String, dynamic>>{
            'router': <String, dynamic>{'error': 'boom'},
          }),
          _obsWithPlugins(<String, Map<String, dynamic>>{
            'router': <String, dynamic>{'error': 'boom'},
          }),
        ],
        tools: tools,
      );
      host.setActiveNamespaces(<String>{'router'});
      final provider = _FakeProvider(script: <ModelDecision>[
        ModelDecision(action: (tool: 'core.wait', args: <String, dynamic>{})),
        ModelDecision(action: (tool: 'core.wait', args: <String, dynamic>{})),
        ModelDecision(action: (tool: 'core.wait', args: <String, dynamic>{})),
      ]);
      final driver = _newDriver(host: host, provider: provider, writer: writer);

      await driver.runTurn();
      await driver.runTurn();
      await driver.runTurn();

      expect(host.disabledPlugins, contains('router'));
      // Exactly one disablePlugin call.
      final disableCalls =
          host.calls.where((c) => c == 'disablePlugin:router').length;
      expect(disableCalls, 1);
      // Exactly one plugin_disabled trajectory record.
      final disabledRecords = sink.lines.where((l) {
        final j = jsonDecode(l);
        return j is Map && j['type'] == 'plugin_disabled';
      }).toList();
      expect(disabledRecords, hasLength(1));
      final j = jsonDecode(disabledRecords.first) as Map<String, dynamic>;
      expect(j['namespace'], 'router');
      expect(j['turn'], 2);
    });

    test('successful plugin observation between failures resets the counter',
        () async {
      final sink = _MemorySink();
      final writer = await _newWriter(sink);
      final host = _FakeHost(
        observations: <Observation>[
          _obsWithPlugins(<String, Map<String, dynamic>>{
            'router': <String, dynamic>{'error': 'boom'},
          }),
          _obsWithPlugins(<String, Map<String, dynamic>>{
            'router': <String, dynamic>{'route': '/home'},
          }),
          _obsWithPlugins(<String, Map<String, dynamic>>{
            'router': <String, dynamic>{'error': 'boom'},
          }),
        ],
        tools: <ToolDescriptor>[_coreWait()],
      );
      host.setActiveNamespaces(<String>{'router'});
      final provider = _FakeProvider(script: <ModelDecision>[
        ModelDecision(action: (tool: 'core.wait', args: <String, dynamic>{})),
        ModelDecision(action: (tool: 'core.wait', args: <String, dynamic>{})),
        ModelDecision(action: (tool: 'core.wait', args: <String, dynamic>{})),
      ]);
      final driver = _newDriver(host: host, provider: provider, writer: writer);

      await driver.runTurn();
      expect(driver.pluginFailures.failuresFor('router'), 1);
      await driver.runTurn();
      expect(driver.pluginFailures.failuresFor('router'), 0);
      await driver.runTurn();
      expect(driver.pluginFailures.failuresFor('router'), 1);
      expect(host.disabledPlugins, isEmpty);
    });
  });

  group(
      'LoopDriver._accountPluginStrikes core-namespace exemption (lenny-4jn)',
      () {
    test(
        'core is never disabled even after 4 turns with no curr.plugins[core]',
        () async {
      final sink = _MemorySink();
      final writer = await _newWriter(sink);
      // 'core' is in activePluginNamespaces; curr.plugins never has 'core'.
      // 'dio' is also active but always absent from plugins — a healthy plugin
      // that simply has nothing to report (no in-flight/recent requests), NOT
      // a failure (lenny-jox).
      final host = _FakeHost(
        observations: List.generate(
          6,
          (_) => _obsWithPlugins(const <String, Map<String, dynamic>>{}),
        ),
        tools: <ToolDescriptor>[
          _coreDone(),
          _coreWait(),
          const ToolDescriptor(
            name: 'dio.fetch',
            description: 'fetch',
            inputSchema: <String, dynamic>{'type': 'object'},
          ),
        ],
      );
      host.setActiveNamespaces(<String>{'core', 'dio'});
      final provider = _FakeProvider(
        script: List.generate(
          4,
          (_) => ModelDecision(
            action: (tool: 'core.wait', args: <String, dynamic>{}),
          ),
        ),
      );
      final driver = _newDriver(host: host, provider: provider, writer: writer);

      for (var i = 0; i < 4; i++) {
        await driver.runTurn();
      }

      expect(
        host.disabledPlugins,
        isNot(contains('core')),
        reason: 'core must never be auto-disabled regardless of how many '
            'turns pass without a curr.plugins[core] entry',
      );
      expect(
        host.mergedTools().map((t) => t.name),
        contains('core.wait'),
        reason: 'core tools must remain in mergedTools after 4 turns',
      );
      expect(
        host.disabledPlugins,
        isNot(contains('dio')),
        reason: 'a plugin that is merely absent from curr.plugins (null '
            'fragment = nothing to report) is healthy and must NOT be '
            'auto-disabled; only an explicit error fragment is a strike '
            '(lenny-jox)',
      );
    });
  });
}
