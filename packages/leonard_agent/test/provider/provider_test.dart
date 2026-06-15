import 'dart:convert';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

ToolDescriptor _t(String n) => ToolDescriptor(
  name: n,
  description: n,
  inputSchema: <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'x': <String, dynamic>{'type': 'integer'},
    },
  },
);

final List<ToolDescriptor> _tap = <ToolDescriptor>[_t('core.tap')];

void main() {
  test('ModelCapabilities typed fields', () {
    const c = ModelCapabilities(
      vision: true,
      preserveThinking: false,
      maxContext: 128000,
      supportsToolUse: true,
    );
    expect(c.vision, isTrue);
    expect(c.preserveThinking, isFalse);
    expect(c.maxContext, 128000);
    expect(c.supportsToolUse, isTrue);
  });

  test('ModelDecision carries action+optional fields', () {
    const d = ModelDecision(
      action: (tool: 'core.tap', args: <String, dynamic>{'node_id': 42}),
      thinking: 'tap the login button',
    );
    expect(d.action.tool, 'core.tap');
    expect(d.action.args['node_id'], 42);
    expect(d.thinking, 'tap the login button');
    expect(d.rationale, isNull);
    expect(d.waitStrategy, isNull);
  });

  test('schema is draft-07 with action oneOf per tool', () {
    final s = ActionSchema.fromToolList(<ToolDescriptor>[
      _t('core.tap'),
      _t('router.push'),
    ]);
    expect(s.jsonSchema[r'$schema'], contains('draft-07'));
    final variants =
        (s.jsonSchema['properties'] as Map<String, dynamic>)['action']['oneOf']
            as List<dynamic>;
    expect(variants.length, 2);
    final names = variants
        .map(
          (dynamic v) =>
              (v as Map<String, dynamic>)['properties']['tool']['const'],
        )
        .toSet();
    expect(names, <String>{'core.tap', 'router.push'});
  });

  test('different tool lists yield non-equal schemas', () {
    final a = ActionSchema.fromToolList(<ToolDescriptor>[
      _t('core.tap'),
      _t('router.push'),
    ]);
    final b = ActionSchema.fromToolList(_tap);
    expect(jsonEncode(a.jsonSchema), isNot(equals(jsonEncode(b.jsonSchema))));
  });

  test('no memoization across calls', () {
    final a = ActionSchema.fromToolList(_tap);
    final b = ActionSchema.fromToolList(_tap);
    expect(identical(a.jsonSchema, b.jsonSchema), isFalse);
    expect(jsonEncode(a.jsonSchema), equals(jsonEncode(b.jsonSchema)));
  });

  test('validate accepts conforming output', () {
    final out = jsonEncode(<String, dynamic>{
      'action': <String, dynamic>{
        'tool': 'core.tap',
        'args': <String, dynamic>{'x': 1},
      },
    });
    final decoded = ActionSchema.fromToolList(_tap).validate(out);
    expect(decoded['action']['tool'], 'core.tap');
  });

  test('validate throws SchemaRejection on unknown tool', () {
    final out = jsonEncode(<String, dynamic>{
      'action': <String, dynamic>{'tool': 'nope', 'args': <String, dynamic>{}},
    });
    expect(
      () => ActionSchema.fromToolList(_tap).validate(out),
      throwsA(isA<SchemaRejection>()),
    );
  });

  test('validate throws SchemaRejection on bad JSON', () {
    expect(
      () => ActionSchema.fromToolList(_tap).validate('{not json'),
      throwsA(
        isA<SchemaRejection>().having(
          (SchemaRejection e) => e.rawOutput,
          'rawOutput',
          '{not json',
        ),
      ),
    );
  });
}
