/// The counting decorator produces the number the spike exists to report.
/// If it miscounts, the go/no-go on phase 2 is made on fiction.
library;

import 'package:leonard_acp/leonard_acp.dart';
import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

/// Replays a scripted sequence of outcomes: a String throws a
/// [SchemaRejection] carrying it, null returns a decision.
class _ScriptedProvider implements ModelProvider {
  _ScriptedProvider(this._script);

  final List<String?> _script;
  int _i = 0;

  @override
  ModelCapabilities get capabilities => kAcpDefaultCapabilities;

  @override
  Stream<ThinkingDelta> thinking() => const Stream<ThinkingDelta>.empty();

  @override
  Future<ModelDecision> decide(
    ConversationSnapshot snapshot,
    ActionSchema schema,
  ) async {
    final String? outcome = _script[_i++];
    if (outcome != null) {
      throw SchemaRejection(validationError: outcome, rawOutput: 'raw');
    }
    return const ModelDecision(
      action: (tool: 'core.done', args: <String, dynamic>{}),
    );
  }
}

ConversationSnapshot get _snapshot => const ConversationSnapshot(
  systemMessage: '',
  turns: <ConversationTurn>[],
  tools: <ToolDescriptor>[],
);

/// A one-tool list: `ActionSchema` composes `action` as a `oneOf` over the
/// tools, and draft-07 rejects an empty `oneOf`, so the list cannot be empty.
ActionSchema get _schema => ActionSchema.fromToolList(const <ToolDescriptor>[
  ToolDescriptor(
    name: 'core.done',
    description: 'done',
    inputSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{},
      'additionalProperties': false,
    },
  ),
]);

Future<void> _run(CountingModelProvider p) async {
  try {
    await p.decide(_snapshot, _schema);
  } on SchemaRejection {
    // counted; the driver owns the retry.
  }
}

void main() {
  test('counts every attempt, rejections included', () async {
    final CountingModelProvider p = CountingModelProvider(
      _ScriptedProvider(<String?>['bad json', null, 'bad json', null]),
    );
    for (int i = 0; i < 4; i++) {
      await _run(p);
    }

    expect(p.attempts, 4);
    expect(p.rejections, 2);
    expect(p.rejectionRate, 0.5);
  });

  test('rethrows so LoopDriver still owns the single retry', () async {
    final CountingModelProvider p = CountingModelProvider(
      _ScriptedProvider(<String?>['nope']),
    );
    await expectLater(
      p.decide(_snapshot, _schema),
      throwsA(isA<SchemaRejection>()),
    );
  });

  test('records reasons in order for the qualitative read', () async {
    final CountingModelProvider p = CountingModelProvider(
      _ScriptedProvider(<String?>['first', 'second']),
    );
    await _run(p);
    await _run(p);

    expect(p.rejectionReasons, <String>['first', 'second']);
  });

  test('rate is zero — not NaN — before anything runs', () {
    final CountingModelProvider p = CountingModelProvider(
      _ScriptedProvider(const <String?>[]),
    );
    expect(p.rejectionRate, 0);
    expect(p.attempts, 0);
  });

  test('times rejected calls as well as successful ones', () async {
    final CountingModelProvider p = CountingModelProvider(
      _ScriptedProvider(<String?>['slow failure']),
    );
    await _run(p);
    expect(p.elapsed, greaterThan(Duration.zero));
  });
}
