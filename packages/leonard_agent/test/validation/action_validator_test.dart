import 'package:leonard_agent/src/observation/models.dart';
import 'package:leonard_agent/src/provider/types.dart';
import 'package:leonard_agent/src/validation/action_validator.dart';
import 'package:leonard_agent/src/validation/result.dart';
import 'package:test/test.dart';

// ---------- Helpers ----------

SemanticsNode _node({
  required int id,
  String role = 'button',
  String label = '',
  List<String> state = const <String>[],
  List<String> actions = const <String>['tap'],
  List<int> rect = const <int>[0, 0, 100, 50],
}) => SemanticsNode(
  id: id,
  role: role,
  label: label,
  state: state,
  actions: actions,
  rect: rect,
);

Observation _obs(List<SemanticsNode> nodes) {
  return Observation(
    core: CoreFragment(
      routeStack: const <String>['/'],
      nodes: <int, SemanticsNode>{for (final n in nodes) n.id: n},
      errors: const <RuntimeError>[],
    ),
    extensions: const <String, ExtensionFragment>{},
    stability: StabilityMetadata.empty,
  );
}

// Schema requiring a single int `node_id`.
Map<String, dynamic> _nodeIdSchema() => <String, dynamic>{
  r'$schema': 'http://json-schema.org/draft-07/schema#',
  'type': 'object',
  'required': <String>['node_id'],
  'properties': <String, dynamic>{
    'node_id': <String, dynamic>{'type': 'integer'},
  },
  'additionalProperties': false,
};

// Schema for scroll_until_visible: scrollable_id + target_id.
Map<String, dynamic> _scrollUntilVisibleSchema() => <String, dynamic>{
  r'$schema': 'http://json-schema.org/draft-07/schema#',
  'type': 'object',
  'required': <String>['scrollable_id', 'target_id'],
  'properties': <String, dynamic>{
    'scrollable_id': <String, dynamic>{'type': 'integer'},
    'target_id': <String, dynamic>{'type': 'integer'},
  },
  'additionalProperties': false,
};

// Schema for an empty-args tool (e.g. wait, done, system_back).
Map<String, dynamic> _emptyArgsSchema() => <String, dynamic>{
  r'$schema': 'http://json-schema.org/draft-07/schema#',
  'type': 'object',
  'properties': <String, dynamic>{},
  'additionalProperties': false,
};

ToolDescriptor _tool(String name, Map<String, dynamic> schema) =>
    ToolDescriptor(name: name, description: 'tool $name', inputSchema: schema);

List<ToolDescriptor> _coreToolList() => <ToolDescriptor>[
  _tool('core.tap', _nodeIdSchema()),
  _tool('core.long_press', _nodeIdSchema()),
  _tool('core.enter_text', <String, dynamic>{
    r'$schema': 'http://json-schema.org/draft-07/schema#',
    'type': 'object',
    'required': <String>['node_id', 'text'],
    'properties': <String, dynamic>{
      'node_id': <String, dynamic>{'type': 'integer'},
      'text': <String, dynamic>{'type': 'string'},
    },
    'additionalProperties': false,
  }),
  _tool('core.scroll', _nodeIdSchema()),
  _tool('core.scroll_until_visible', _scrollUntilVisibleSchema()),
  _tool('core.inspect_widget', _nodeIdSchema()),
  _tool('core.gesture', _nodeIdSchema()),
  _tool('core.system_back', _emptyArgsSchema()),
  _tool('core.wait', _emptyArgsSchema()),
  _tool('core.done', _emptyArgsSchema()),
  _tool('router.push', <String, dynamic>{
    r'$schema': 'http://json-schema.org/draft-07/schema#',
    'type': 'object',
    'required': <String>['path'],
    'properties': <String, dynamic>{
      'path': <String, dynamic>{'type': 'string'},
    },
    'additionalProperties': false,
  }),
];

// ---------- Tests ----------

void main() {
  const validator = ActionValidator();

  group('ValidationOk', () {
    test('returns ok for a well-formed core.tap on an enabled node', () {
      final obs = _obs(<SemanticsNode>[_node(id: 1)]);
      final r = validator.validate(
        (tool: 'core.tap', args: <String, dynamic>{'node_id': 1}),
        obs,
        _coreToolList(),
      );
      expect(r, isA<ValidationOk>());
    });

    test('returns ok for extension tool that passes schema, no node check', () {
      final obs = _obs(const <SemanticsNode>[]);
      final r = validator.validate(
        (tool: 'router.push', args: <String, dynamic>{'path': '/x'}),
        obs,
        _coreToolList(),
      );
      expect(r, isA<ValidationOk>());
    });

    test('returns ok for core.system_back / core.wait / core.done '
        '(no node pass)', () {
      final obs = _obs(const <SemanticsNode>[]);
      for (final name in <String>[
        'core.system_back',
        'core.wait',
        'core.done',
      ]) {
        final r = validator.validate(
          (tool: name, args: const <String, dynamic>{}),
          obs,
          _coreToolList(),
        );
        expect(r, isA<ValidationOk>(), reason: name);
      }
    });
  });

  group('unknown_tool', () {
    test('rejects with expected populated', () {
      final obs = _obs(const <SemanticsNode>[]);
      final r = validator.validate(
        (tool: 'core.fly', args: const <String, dynamic>{}),
        obs,
        _coreToolList(),
      );
      expect(r, isA<ValidationReject>());
      final rej = r as ValidationReject;
      expect(rej.tool, 'core.fly');
      expect(rej.reason, 'unknown_tool');
      expect(rej.got, 'core.fly');
      expect(rej.expected, isNotNull);
      expect(rej.expected, contains('core.tap'));
      expect(rej.expected, contains('router.push'));
    });
  });

  group('schema_invalid', () {
    test(
      'rejects when required arg is missing, with pointer + description',
      () {
        final obs = _obs(<SemanticsNode>[_node(id: 1)]);
        final r = validator.validate(
          (tool: 'core.tap', args: const <String, dynamic>{}),
          obs,
          _coreToolList(),
        );
        expect(r, isA<ValidationReject>());
        final rej = r as ValidationReject;
        expect(rej.reason, 'schema_invalid');
        expect(rej.pointer, isNotNull);
        expect(rej.description, isNotNull);
        expect(rej.description, isNotEmpty);
      },
    );

    test('rejects when arg type is wrong', () {
      final obs = _obs(<SemanticsNode>[_node(id: 1)]);
      final r = validator.validate(
        (tool: 'core.tap', args: const <String, dynamic>{'node_id': 'one'}),
        obs,
        _coreToolList(),
      );
      expect(r, isA<ValidationReject>());
      final rej = r as ValidationReject;
      expect(rej.reason, 'schema_invalid');
      expect(rej.pointer, isNotNull);
    });

    test('rejects when extra arg violates additionalProperties: false', () {
      final obs = _obs(<SemanticsNode>[_node(id: 1)]);
      final r = validator.validate(
        (
          tool: 'core.tap',
          args: const <String, dynamic>{'node_id': 1, 'extra': 'no'},
        ),
        obs,
        _coreToolList(),
      );
      expect(r, isA<ValidationReject>());
      expect((r as ValidationReject).reason, 'schema_invalid');
    });
  });

  group('node_not_found', () {
    test('for core.tap when node_id is absent from observation', () {
      final obs = _obs(<SemanticsNode>[_node(id: 1)]);
      final r = validator.validate(
        (tool: 'core.tap', args: const <String, dynamic>{'node_id': 99}),
        obs,
        _coreToolList(),
      );
      final rej = r as ValidationReject;
      expect(rej.reason, 'node_not_found');
      expect(rej.pointer, '/node_id');
      expect(rej.got, 99);
    });

    test('for each core node-tool variant', () {
      final obs = _obs(<SemanticsNode>[_node(id: 1)]);
      final cases = <({String tool, Map<String, dynamic> args})>[
        (tool: 'core.tap', args: <String, dynamic>{'node_id': 99}),
        (tool: 'core.long_press', args: <String, dynamic>{'node_id': 99}),
        (
          tool: 'core.enter_text',
          args: <String, dynamic>{'node_id': 99, 'text': 'x'},
        ),
        (tool: 'core.scroll', args: <String, dynamic>{'node_id': 99}),
        (tool: 'core.inspect_widget', args: <String, dynamic>{'node_id': 99}),
        (tool: 'core.gesture', args: <String, dynamic>{'node_id': 99}),
      ];
      for (final c in cases) {
        final r = validator.validate(c, obs, _coreToolList());
        expect(r, isA<ValidationReject>(), reason: c.tool);
        final rej = r as ValidationReject;
        expect(rej.reason, 'node_not_found', reason: c.tool);
      }
    });
  });

  group('node_disabled', () {
    test('when node exists but state contains "disabled"', () {
      final obs = _obs(<SemanticsNode>[
        _node(id: 1, state: const <String>['disabled']),
      ]);
      final r = validator.validate(
        (tool: 'core.tap', args: const <String, dynamic>{'node_id': 1}),
        obs,
        _coreToolList(),
      );
      final rej = r as ValidationReject;
      expect(rej.reason, 'node_disabled');
      expect(rej.pointer, '/node_id');
      expect(rej.got, 1);
    });

    test('does not trigger when state lacks "disabled"', () {
      final obs = _obs(<SemanticsNode>[
        _node(id: 1, state: const <String>['focused', 'checked']),
      ]);
      final r = validator.validate(
        (tool: 'core.tap', args: const <String, dynamic>{'node_id': 1}),
        obs,
        _coreToolList(),
      );
      expect(r, isA<ValidationOk>());
    });
  });

  group('core.scroll_until_visible', () {
    test('checks both scrollable_id and target_id (scrollable missing)', () {
      final obs = _obs(<SemanticsNode>[_node(id: 2)]);
      final r = validator.validate(
        (
          tool: 'core.scroll_until_visible',
          args: const <String, dynamic>{'scrollable_id': 99, 'target_id': 2},
        ),
        obs,
        _coreToolList(),
      );
      final rej = r as ValidationReject;
      expect(rej.reason, 'node_not_found');
      expect(rej.pointer, '/scrollable_id');
      expect(rej.got, 99);
    });

    test('checks both scrollable_id and target_id (target missing)', () {
      final obs = _obs(<SemanticsNode>[_node(id: 1)]);
      final r = validator.validate(
        (
          tool: 'core.scroll_until_visible',
          args: const <String, dynamic>{'scrollable_id': 1, 'target_id': 99},
        ),
        obs,
        _coreToolList(),
      );
      final rej = r as ValidationReject;
      expect(rej.reason, 'node_not_found');
      expect(rej.pointer, '/target_id');
      expect(rej.got, 99);
    });

    test('rejects target_id when it is disabled', () {
      final obs = _obs(<SemanticsNode>[
        _node(id: 1),
        _node(id: 2, state: const <String>['disabled']),
      ]);
      final r = validator.validate(
        (
          tool: 'core.scroll_until_visible',
          args: const <String, dynamic>{'scrollable_id': 1, 'target_id': 2},
        ),
        obs,
        _coreToolList(),
      );
      final rej = r as ValidationReject;
      expect(rej.reason, 'node_disabled');
      expect(rej.pointer, '/target_id');
    });

    test('returns ok when both nodes are present and enabled', () {
      final obs = _obs(<SemanticsNode>[_node(id: 1), _node(id: 2)]);
      final r = validator.validate(
        (
          tool: 'core.scroll_until_visible',
          args: const <String, dynamic>{'scrollable_id': 1, 'target_id': 2},
        ),
        obs,
        _coreToolList(),
      );
      expect(r, isA<ValidationOk>());
    });
  });

  group('statelessness', () {
    test('repeated calls with same inputs return equal results', () {
      final obs = _obs(<SemanticsNode>[_node(id: 1)]);
      final tools = _coreToolList();
      final r1 = validator.validate(
        (tool: 'core.tap', args: const <String, dynamic>{'node_id': 99}),
        obs,
        tools,
      );
      final r2 = validator.validate(
        (tool: 'core.tap', args: const <String, dynamic>{'node_id': 99}),
        obs,
        tools,
      );
      expect(r1, equals(r2));
    });

    test('ok results are equal across calls', () {
      final obs = _obs(<SemanticsNode>[_node(id: 1)]);
      final tools = _coreToolList();
      final r1 = validator.validate(
        (tool: 'core.tap', args: const <String, dynamic>{'node_id': 1}),
        obs,
        tools,
      );
      final r2 = validator.validate(
        (tool: 'core.tap', args: const <String, dynamic>{'node_id': 1}),
        obs,
        tools,
      );
      expect(r1, equals(r2));
    });
  });

  group('first match wins ordering', () {
    test('unknown_tool fires before schema check', () {
      final obs = _obs(const <SemanticsNode>[]);
      final r = validator.validate(
        (
          tool: 'core.fly',
          args: const <String, dynamic>{'node_id': 'not-an-int'},
        ),
        obs,
        _coreToolList(),
      );
      expect((r as ValidationReject).reason, 'unknown_tool');
    });

    test('schema_invalid fires before node check', () {
      final obs = _obs(const <SemanticsNode>[]);
      final r = validator.validate(
        (tool: 'core.tap', args: const <String, dynamic>{}),
        obs,
        _coreToolList(),
      );
      // node 99 doesn't exist, but schema fires first because node_id missing.
      expect((r as ValidationReject).reason, 'schema_invalid');
    });
  });
}
