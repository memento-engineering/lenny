import 'dart:convert';

import 'package:exploration_agent/exploration_agent.dart';
import 'package:test/test.dart';

const String _agents = '# AGENTS.md\nFollow these rules.';
const String _goal = 'Open the settings screen and toggle dark mode.';

ObservationDiff _emptyDiff() => const ObservationDiff(
      core: CoreDiff(
        routeChanges: <RouteChange>[],
        nodesAdded: <SemanticsNode>[],
        nodesRemoved: <int>[],
        nodesChanged: <NodeChange>[],
        errorsAdded: <RuntimeError>[],
      ),
      plugins: <String, PluginDiff>{},
    );

class _Counter implements TokenCounter {
  const _Counter();
  @override
  int count(String text) => 0;
}

RunningSummary _summary({String text = ''}) {
  final RunningSummary s = RunningSummary(counter: const _Counter());
  if (text.isNotEmpty) s.update(text);
  return s;
}

ActionRing _ring(List<String> entries) {
  final ActionRing r = ActionRing();
  for (final String e in entries) {
    r.push(e);
  }
  return r;
}

ToolDescriptor _tool(String name) => ToolDescriptor(
      name: name,
      description: 'desc:$name',
      inputSchema: <String, dynamic>{
        r'$schema': 'http://json-schema.org/draft-07/schema#',
        'type': 'object',
        'properties': <String, dynamic>{},
      },
    );

void main() {
  group('PromptAssembler.assemble', () {
    const PromptAssembler a = PromptAssembler();

    test('systemMessage embeds AGENTS.md, goal, summary, and actions verbatim',
        () {
      final RunningSummary s = _summary(text: 'short summary so far');
      final ActionRing ring = _ring(<String>['tap(button:42)', 'wait(idle)']);
      final PromptPayload p = a.assemble(
        agentsMd: _agents,
        goal: _goal,
        summary: s,
        actionRing: ring,
        observation: Observation.empty(),
        diff: _emptyDiff(),
        mergedTools: <ToolDescriptor>[_tool('core.tap')],
      );

      expect(p.systemMessage, contains(_agents));
      expect(p.systemMessage, contains(_goal));
      expect(p.systemMessage, contains('short summary so far'));
      expect(p.systemMessage, contains('tap(button:42)'));
      expect(p.systemMessage, contains('wait(idle)'));
    });

    test('empty action ring produces a placeholder, not an exception', () {
      final PromptPayload p = a.assemble(
        agentsMd: _agents,
        goal: _goal,
        summary: _summary(),
        actionRing: _ring(<String>[]),
        observation: Observation.empty(),
        diff: _emptyDiff(),
        mergedTools: <ToolDescriptor>[],
      );
      expect(p.systemMessage, contains('Recent actions'));
      expect(p.systemMessage, contains('(none yet)'));
    });

    test('userMessages carries serialized observation and diff', () {
      final Observation obs = Observation.empty();
      final ObservationDiff diff = _emptyDiff();
      final PromptPayload p = a.assemble(
        agentsMd: _agents,
        goal: _goal,
        summary: _summary(),
        actionRing: _ring(<String>[]),
        observation: obs,
        diff: diff,
        mergedTools: <ToolDescriptor>[],
      );
      expect(p.userMessages, hasLength(2));
      expect(p.userMessages[0]['type'], 'text');
      expect(p.userMessages[0]['text'], contains('Observation:'));
      expect(p.userMessages[0]['text'], contains(jsonEncode(obs.toJson())));
      expect(p.userMessages[1]['text'], contains('Diff since last turn:'));
      expect(p.userMessages[1]['text'], contains(jsonEncode(diff.toJson())));
    });

    test('tools list passes through unchanged (same names + schemas)', () {
      final List<ToolDescriptor> tools = <ToolDescriptor>[
        _tool('core.tap'),
        _tool('router.push'),
        _tool('core.wait'),
      ];
      final PromptPayload p = a.assemble(
        agentsMd: _agents,
        goal: _goal,
        summary: _summary(),
        actionRing: _ring(<String>[]),
        observation: Observation.empty(),
        diff: _emptyDiff(),
        mergedTools: tools,
      );
      expect(
        p.tools.map((ToolDescriptor t) => t.name).toList(),
        <String>['core.tap', 'router.push', 'core.wait'],
      );
      expect(p.tools[0].description, 'desc:core.tap');
      expect(
        p.tools[0].inputSchema[r'$schema'],
        'http://json-schema.org/draft-07/schema#',
      );
    });

    test('tool entries are typed ToolDescriptor', () {
      final PromptPayload p = a.assemble(
        agentsMd: _agents,
        goal: _goal,
        summary: _summary(),
        actionRing: _ring(<String>[]),
        observation: Observation.empty(),
        diff: _emptyDiff(),
        mergedTools: <ToolDescriptor>[_tool('core.tap')],
      );
      expect(p.tools, isA<List<ToolDescriptor>>());
      expect(p.tools.first, isA<ToolDescriptor>());
    });

    test('pure: structurally equal inputs yield structurally equal outputs',
        () {
      PromptPayload build() => a.assemble(
            agentsMd: _agents,
            goal: _goal,
            summary: _summary(text: 'same'),
            actionRing: _ring(<String>['x', 'y']),
            observation: Observation.empty(),
            diff: _emptyDiff(),
            mergedTools: <ToolDescriptor>[_tool('core.tap')],
          );
      final PromptPayload p1 = build();
      final PromptPayload p2 = build();
      expect(p1.systemMessage, p2.systemMessage);
      expect(jsonEncode(p1.userMessages), jsonEncode(p2.userMessages));
      expect(p1.tools.length, p2.tools.length);
      for (int i = 0; i < p1.tools.length; i++) {
        expect(p1.tools[i].name, p2.tools[i].name);
        expect(p1.tools[i].description, p2.tools[i].description);
        expect(
          jsonEncode(p1.tools[i].inputSchema),
          jsonEncode(p2.tools[i].inputSchema),
        );
      }
    });

    test('different mergedTools produces matching delta in payload.tools', () {
      final List<ToolDescriptor> withFoo = <ToolDescriptor>[
        _tool('core.tap'),
        _tool('foo.bar'),
      ];
      final List<ToolDescriptor> withoutFoo = <ToolDescriptor>[
        _tool('core.tap'),
      ];

      PromptPayload run(List<ToolDescriptor> tools) => a.assemble(
            agentsMd: _agents,
            goal: _goal,
            summary: _summary(),
            actionRing: _ring(<String>[]),
            observation: Observation.empty(),
            diff: _emptyDiff(),
            mergedTools: tools,
          );

      final PromptPayload pAll = run(withFoo);
      final PromptPayload pCore = run(withoutFoo);

      expect(
        pAll.tools.map((ToolDescriptor t) => t.name).toList(),
        <String>['core.tap', 'foo.bar'],
      );
      expect(
        pCore.tools.map((ToolDescriptor t) => t.name).toList(),
        <String>['core.tap'],
      );
      // The delta is exactly `foo.bar` — proving no caching/memoization.
      final Set<String> diff = pAll.tools
          .map((ToolDescriptor t) => t.name)
          .toSet()
          .difference(pCore.tools.map((ToolDescriptor t) => t.name).toSet());
      expect(diff, <String>{'foo.bar'});
    });

    test('tools list in payload is unmodifiable', () {
      final PromptPayload p = a.assemble(
        agentsMd: _agents,
        goal: _goal,
        summary: _summary(),
        actionRing: _ring(<String>[]),
        observation: Observation.empty(),
        diff: _emptyDiff(),
        mergedTools: <ToolDescriptor>[_tool('core.tap')],
      );
      expect(() => p.tools.add(_tool('x')), throwsUnsupportedError);
    });
  });
}
