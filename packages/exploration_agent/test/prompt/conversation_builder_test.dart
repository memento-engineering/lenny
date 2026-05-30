import 'dart:convert';

import 'package:exploration_agent/exploration_agent.dart';
import 'package:test/test.dart';

const ToolDescriptor _coreDone = ToolDescriptor(
  name: 'core.done',
  description: 'declare done',
  inputSchema: <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'reason': <String, dynamic>{'type': 'string'},
    },
    'required': <String>['reason'],
  },
);

Observation _obsWithRoute(String route) => Observation.fromJson(<String, dynamic>{
      'semantics': <Map<String, dynamic>>[],
      'routes': <String>[route],
      'errors': <Map<String, dynamic>>[],
      'stability': <String, dynamic>{
        'policy': 'action_relative',
        'terminated_by': 'idle',
        'duration_ms': 1,
        'framework_busy': false,
        'plugins_busy': <String>[],
      },
    });

Observation _obsWithScreenshot(String b64) => Observation.fromJson(<String, dynamic>{
      'semantics': <Map<String, dynamic>>[],
      'routes': <String>['/'],
      'errors': <Map<String, dynamic>>[],
      'stability': <String, dynamic>{
        'policy': 'action_relative',
        'terminated_by': 'idle',
        'duration_ms': 1,
        'framework_busy': false,
        'plugins_busy': <String>[],
      },
      'screenshot_png_b64': b64,
    });

ObservationDiff _emptyDiff() => ObservationDiff.empty();

void main() {
  group('ConversationBuilder.snapshot — system message identity', () {
    test('systemMessage is referentially identical across snapshots', () {
      final ConversationBuilder b = ConversationBuilder(
        systemMessage: 'AGENTS\n\n## Goal\nexplore',
        tools: const <ToolDescriptor>[_coreDone],
      );
      final ConversationSnapshot s1 = b.snapshot();
      b.appendUserTurn(Observation.empty(), _emptyDiff());
      final ConversationSnapshot s2 = b.snapshot();
      expect(identical(s1.systemMessage, s2.systemMessage), isTrue);
    });

    test('snapshot turns list is unmodifiable', () {
      final ConversationBuilder b = ConversationBuilder(
        systemMessage: 'sys',
        tools: const <ToolDescriptor>[_coreDone],
      );
      b.appendUserTurn(Observation.empty(), _emptyDiff());
      final ConversationSnapshot s = b.snapshot();
      expect(() => s.turns.removeAt(0), throwsUnsupportedError);
    });
  });

  group('ConversationBuilder.append* — grow turns by one', () {
    test('appendUserTurn grows turns by exactly one', () {
      final ConversationBuilder b = ConversationBuilder(
        systemMessage: 'sys',
        tools: const <ToolDescriptor>[_coreDone],
      );
      expect(b.snapshot().turns, isEmpty);
      b.appendUserTurn(Observation.empty(), _emptyDiff());
      expect(b.snapshot().turns.length, equals(1));
      expect(b.snapshot().turns.first, isA<UserTurn>());
    });

    test('appendAssistantTurn grows turns by exactly one', () {
      final ConversationBuilder b = ConversationBuilder(
        systemMessage: 'sys',
        tools: const <ToolDescriptor>[_coreDone],
      );
      b.appendUserTurn(Observation.empty(), _emptyDiff());
      b.appendAssistantTurn(
        'reasoning text',
        (tool: 'core.done', args: <String, dynamic>{'reason': 'finished'}),
      );
      expect(b.snapshot().turns.length, equals(2));
      expect(b.snapshot().turns.last, isA<AssistantTurn>());
      final AssistantTurn at = b.snapshot().turns.last as AssistantTurn;
      expect(at.thinking, equals('reasoning text'));
      expect(at.action.tool, equals('core.done'));
    });

    test('toolResult on UserTurn is preserved through snapshot', () {
      final ConversationBuilder b = ConversationBuilder(
        systemMessage: 'sys',
        tools: const <ToolDescriptor>[_coreDone],
      );
      b.appendUserTurn(
        Observation.empty(),
        _emptyDiff(),
        toolResult: <String, dynamic>{'error': 'bad_args'},
      );
      final UserTurn ut = b.snapshot().turns.first as UserTurn;
      expect(ut.toolResult, equals(<String, dynamic>{'error': 'bad_args'}));
    });
  });

  group('ConversationBuilder.trimIfOverBudget', () {
    test('replaces oldest non-trimmed observation with Observation.empty', () {
      final ConversationBuilder b = ConversationBuilder(
        systemMessage: 'sys',
        tools: const <ToolDescriptor>[_coreDone],
      );
      // Build several "fat" turns by including a screenshot — flat 1500
      // tokens accounted per screenshot — to force the budget over.
      b.appendUserTurn(_obsWithScreenshot('a' * 100), _emptyDiff());
      b.appendUserTurn(_obsWithScreenshot('b' * 100), _emptyDiff());
      b.appendUserTurn(_obsWithScreenshot('c' * 100), _emptyDiff());
      // Pre-trim: 3 non-trimmed UserTurns.
      expect(
        b.snapshot().turns
            .whereType<UserTurn>()
            .where((UserTurn u) => !u.trimmed)
            .length,
        equals(3),
      );
      // Aggressive threshold to force trim of the oldest first.
      b.trimIfOverBudget(2000);
      final List<UserTurn> userTurns =
          b.snapshot().turns.whereType<UserTurn>().toList();
      // Oldest is trimmed; later ones are not (until budget is satisfied).
      expect(userTurns.first.trimmed, isTrue);
      expect(userTurns.first.observation.screenshot, isNull);
    });

    test('trimmed turn preserves its diff', () {
      final ConversationBuilder b = ConversationBuilder(
        systemMessage: 'sys',
        tools: const <ToolDescriptor>[_coreDone],
      );
      // Pre-compute a diff that differs from ObservationDiff.empty()
      // (route changed) so we can detect preservation post-trim.
      final ObservationDiff diff =
          ObservationDiffer.diff(Observation.empty(), _obsWithRoute('/home'));
      b.appendUserTurn(_obsWithScreenshot('x' * 100), diff);
      b.appendUserTurn(_obsWithScreenshot('y' * 100), _emptyDiff());
      b.trimIfOverBudget(1500);
      final UserTurn trimmed =
          b.snapshot().turns.whereType<UserTurn>().first;
      expect(trimmed.trimmed, isTrue);
      // The route change in core.routeChanges survives trim.
      expect(trimmed.diff.core.routeChanges, isNotEmpty);
    });

    test('stops trimming once budget is met', () {
      final ConversationBuilder b = ConversationBuilder(
        systemMessage: 'sys',
        tools: const <ToolDescriptor>[_coreDone],
      );
      b.appendUserTurn(Observation.empty(), _emptyDiff());
      b.appendUserTurn(Observation.empty(), _emptyDiff());
      // Generous threshold — nothing needs trimming.
      b.trimIfOverBudget(100000);
      final List<UserTurn> uts =
          b.snapshot().turns.whereType<UserTurn>().toList();
      expect(uts.every((UserTurn u) => !u.trimmed), isTrue);
    });
  });

  group('JsonObservationRenderer', () {
    test('output is valid JSON with stable top-level keys', () {
      const JsonObservationRenderer r = JsonObservationRenderer();
      final String rendered = r.render(Observation.empty());
      final Object? decoded = jsonDecode(rendered);
      expect(decoded, isA<Map<String, dynamic>>());
      final Map<String, dynamic> m = decoded! as Map<String, dynamic>;
      expect(m.keys.toSet(), containsAll(<String>{'core', 'plugins', 'stability'}));
    });

    test('round-trips Observation by value through fromJson', () {
      const JsonObservationRenderer r = JsonObservationRenderer();
      final Observation original = _obsWithRoute('/home');
      final String rendered = r.render(original);
      final Map<String, dynamic> decoded =
          (jsonDecode(rendered) as Map).cast<String, dynamic>();
      // The renderer emits core/plugins/stability — reconstructable but
      // not in the binding's flat wire format; build a fromJson-shaped
      // map from the renderer output's core fields.
      final Map<String, dynamic> flat = <String, dynamic>{
        'semantics': (decoded['core'] as Map)['nodes'] ?? <dynamic>[],
        'routes': ((decoded['core'] as Map)['routeStack'] as List).cast<String>(),
        'errors': (decoded['core'] as Map)['errors'] ?? <dynamic>[],
        'stability': decoded['stability'],
        'plugins': decoded['plugins'],
      };
      final Observation restored = Observation.fromJson(flat);
      expect(restored.core.routeStack, equals(original.core.routeStack));
      expect(restored.stability, equals(original.stability));
    });
  });
}
