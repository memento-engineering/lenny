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

List<ToolDescriptor> _strictNormalizationTools() => <ToolDescriptor>[
  ToolDescriptor(
    name: 'core.numeric',
    description: 'accept numeric arguments',
    inputSchema: const <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'count': <String, dynamic>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 10,
        },
        'nullable_count': <String, dynamic>{
          'type': <String>['integer', 'null'],
        },
        'direct_count': <String, dynamic>{'type': 'integer'},
        'whole_count': <String, dynamic>{'type': 'integer'},
        'numbers': <String, dynamic>{
          'type': 'array',
          'items': <String, dynamic>{'type': 'number'},
        },
        'nested': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'count': <String, dynamic>{'type': 'integer'},
          },
          'required': <String>['count'],
          'additionalProperties': false,
        },
        'label': <String, dynamic>{'type': 'string', 'maxLength': 4},
      },
      'required': <String>[
        'count',
        'nullable_count',
        'direct_count',
        'whole_count',
        'numbers',
        'nested',
        'label',
      ],
      'additionalProperties': false,
    },
  ),
  ToolDescriptor(
    name: 'core.text',
    description: 'accept a string argument',
    inputSchema: const <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'count': <String, dynamic>{'type': 'string'},
      },
      'required': <String>['count'],
      'additionalProperties': false,
    },
  ),
];

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

  test('ModelDecision carries provider response metadata', () {
    const withoutMetadata = ModelDecision(
      action: (tool: 'core.wait', args: <String, dynamic>{}),
    );
    expect(withoutMetadata.modelMetadata, isEmpty);

    const withMetadata = ModelDecision(
      action: (tool: 'core.wait', args: <String, dynamic>{}),
      providerRequestId: 'msg_42',
      modelMetadata: <String, dynamic>{
        'served_model_id': 'qwen',
        'provider_request_id': 'msg_42',
      },
    );
    expect(withMetadata.modelMetadata, <String, dynamic>{
      'served_model_id': 'qwen',
      'provider_request_id': 'msg_42',
    });
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

  test('normalizes only schema-declared lossless numeric values', () {
    final schema = ActionSchema.fromToolList(_strictNormalizationTools());
    final transported = ActionSchema.fromJson(
      jsonDecode(jsonEncode(schema.toJson())) as Map<String, dynamic>,
    );
    final schemaSnapshot = jsonEncode(schema.jsonSchema);
    final transportedSnapshot = jsonEncode(transported.jsonSchema);
    final cases =
        <
          ({
            ActionSchema schema,
            String tool,
            Map<String, dynamic> input,
            Map<String, dynamic> expected,
          })
        >[
          (
            schema: schema,
            tool: 'core.numeric',
            input: <String, dynamic>{
              'count': ' 5.0 ',
              'nullable_count': ' 2 ',
              'direct_count': 4,
              'whole_count': 6.0,
              'numbers': <Object>[7, 8.5, ' 9.25 ', '1e0'],
              'nested': <String, dynamic>{'count': '3e0'},
              'label': '123',
            },
            expected: <String, dynamic>{
              'count': 5,
              'nullable_count': 2,
              'direct_count': 4,
              'whole_count': 6,
              'numbers': <Object>[7, 8.5, 9.25, 1.0],
              'nested': <String, dynamic>{'count': 3},
              'label': '123',
            },
          ),
          (
            schema: transported,
            tool: 'core.text',
            input: <String, dynamic>{'count': '5'},
            expected: <String, dynamic>{'count': '5'},
          ),
        ];

    for (final testCase in cases) {
      final decoded = testCase.schema.validate(
        jsonEncode(<String, dynamic>{
          'action': <String, dynamic>{
            'tool': testCase.tool,
            'args': testCase.input,
          },
        }),
      );
      expect(decoded['action']['args'], testCase.expected);
    }

    expect(jsonEncode(schema.jsonSchema), schemaSnapshot);
    expect(jsonEncode(schema.toJson()), schemaSnapshot);
    expect(jsonEncode(transported.jsonSchema), transportedSnapshot);
    expect(jsonEncode(transported.toJson()), transportedSnapshot);
  });

  test(
    'rejects invalid numeric representations and remaining schema violations',
    () {
      final schema = ActionSchema.fromToolList(_strictNormalizationTools());
      final validArgs = <String, dynamic>{
        'count': 5,
        'nullable_count': 2,
        'direct_count': 4,
        'whole_count': 6,
        'numbers': <Object>[1],
        'nested': <String, dynamic>{'count': 3},
        'label': 'ok',
      };
      final missingRequired = Map<String, dynamic>.from(validArgs)
        ..remove('count');
      final cases = <({String description, Map<String, dynamic> args})>[
        (
          description: 'nonnumeric integer string',
          args: <String, dynamic>{...validArgs, 'count': 'abc'},
        ),
        (
          description: 'NaN number string',
          args: <String, dynamic>{
            ...validArgs,
            'numbers': <Object>['NaN'],
          },
        ),
        (
          description: 'infinite number string',
          args: <String, dynamic>{
            ...validArgs,
            'numbers': <Object>['Infinity'],
          },
        ),
        (
          description: 'boolean integer',
          args: <String, dynamic>{...validArgs, 'count': true},
        ),
        (
          description: 'fractional integer number',
          args: <String, dynamic>{...validArgs, 'count': 5.5},
        ),
        (
          description: 'fractional integer string',
          args: <String, dynamic>{...validArgs, 'count': '5.5'},
        ),
        (
          description: 'string over maxLength',
          args: <String, dynamic>{...validArgs, 'label': '12345'},
        ),
        (
          description: 'additional property',
          args: <String, dynamic>{...validArgs, 'extra': 1},
        ),
        (description: 'missing required property', args: missingRequired),
        (
          description: 'numeric string below minimum',
          args: <String, dynamic>{...validArgs, 'count': '0'},
        ),
        (
          description: 'numeric string above maximum',
          args: <String, dynamic>{...validArgs, 'count': '11'},
        ),
      ];

      for (final testCase in cases) {
        final rawOutput = jsonEncode(<String, dynamic>{
          'action': <String, dynamic>{
            'tool': 'core.numeric',
            'args': testCase.args,
          },
        });
        expect(
          () => schema.validate(rawOutput),
          throwsA(
            isA<SchemaRejection>().having(
              (error) => error.rawOutput,
              '${testCase.description} rawOutput',
              rawOutput,
            ),
          ),
          reason: testCase.description,
        );
      }
    },
  );

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
