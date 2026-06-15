import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

class _ScriptedProvider extends ModelProvider {
  _ScriptedProvider(this._script);

  final List<Object> _script; // entries: ModelDecision or SchemaRejection
  int _i = 0;
  int get callCount => _i;

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
    if (_i >= _script.length) {
      throw StateError('no more scripted decisions');
    }
    final entry = _script[_i++];
    if (entry is SchemaRejection) throw entry;
    if (entry is ModelDecision) return entry;
    throw StateError('bad scripted entry: $entry');
  }
}

ModelDecision _decision(String tool, [Map<String, dynamic>? args]) =>
    ModelDecision(action: (tool: tool, args: args ?? const <String, dynamic>{}));

ConversationSnapshot _baseSnapshot(List<ToolDescriptor> tools) {
  final builder = ConversationBuilder(
    systemMessage: 'sys',
    tools: tools,
  );
  builder.appendUserTurn(Observation.empty(), ObservationDiff.empty());
  return builder.snapshot();
}

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

void main() {
  group('decideAndValidate', () {
    final tools = <ToolDescriptor>[_coreDone(), _coreWait()];
    final schema = ActionSchema.fromToolList(tools);
    final validator = const ActionValidator();
    final observation = Observation.empty();

    test('first decision valid → retries=0', () async {
      final provider = _ScriptedProvider(<Object>[_decision('core.done')]);
      final r = await decideAndValidate(
        provider: provider,
        baseSnapshot: _baseSnapshot(tools),
        schema: schema,
        validator: validator,
        observation: observation,
        mergedTools: tools,
      );
      expect(r.retries, 0);
      expect(r.rejections, isEmpty);
      expect(r.schemaRetries, 0);
      expect(r.decision.action.tool, 'core.done');
      expect(provider.callCount, 1);
    });

    test('two validator rejects then valid → retries=2', () async {
      // Three scripted decisions: two unknown_tool rejections, then a
      // valid one. Validator rejects 'bogus.x' and 'also.bogus', accepts
      // 'core.done'.
      final provider = _ScriptedProvider(<Object>[
        _decision('bogus.x'),
        _decision('also.bogus'),
        _decision('core.done'),
      ]);
      final r = await decideAndValidate(
        provider: provider,
        baseSnapshot: _baseSnapshot(tools),
        schema: schema,
        validator: validator,
        observation: observation,
        mergedTools: tools,
      );
      expect(r.retries, 2);
      expect(r.rejections, hasLength(2));
      // Each rejection is a JSON message containing the bad tool name.
      expect(r.rejections[0], contains('"tool":"bogus.x"'));
      expect(r.rejections[1], contains('"tool":"also.bogus"'));
    });

    test('four validator rejects → throws InvalidActionExhausted', () async {
      final provider = _ScriptedProvider(<Object>[
        _decision('a.bad'),
        _decision('b.bad'),
        _decision('c.bad'),
        _decision('d.bad'),
      ]);
      try {
        await decideAndValidate(
          provider: provider,
          baseSnapshot: _baseSnapshot(tools),
          schema: schema,
          validator: validator,
          observation: observation,
          mergedTools: tools,
        );
        fail('expected InvalidActionExhausted');
      } on InvalidActionExhausted catch (e) {
        expect(e.rejections, hasLength(4));
      }
    });

    test('one schema rejection then valid → succeeds with schemaRetries=1',
        () async {
      final provider = _ScriptedProvider(<Object>[
        const SchemaRejection(
          validationError: 'missing required field action',
          rawOutput: '{}',
        ),
        _decision('core.done'),
      ]);
      final r = await decideAndValidate(
        provider: provider,
        baseSnapshot: _baseSnapshot(tools),
        schema: schema,
        validator: validator,
        observation: observation,
        mergedTools: tools,
      );
      expect(r.schemaRetries, 1);
      expect(r.retries, 0);
      expect(r.decision.action.tool, 'core.done');
    });

    test('two schema rejections → throws SchemaExhausted', () async {
      final provider = _ScriptedProvider(<Object>[
        const SchemaRejection(
          validationError: 'missing required field action',
          rawOutput: '{}',
        ),
        const SchemaRejection(
          validationError: 'still wrong',
          rawOutput: '{"x":1}',
        ),
      ]);
      try {
        await decideAndValidate(
          provider: provider,
          baseSnapshot: _baseSnapshot(tools),
          schema: schema,
          validator: validator,
          observation: observation,
          mergedTools: tools,
        );
        fail('expected SchemaExhausted');
      } on SchemaExhausted catch (e) {
        expect(e.cause.validationError, 'still wrong');
      }
    });
  });
}
