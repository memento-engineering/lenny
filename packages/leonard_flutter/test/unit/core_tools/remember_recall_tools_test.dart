import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('core.remember and core.recall round-trip bytes exactly', () async {
    final SemanticsCapture capture = SemanticsCapture();
    final CoreExtension extension = CoreExtension(semantics: capture);
    final LeonardTool remember = _tool(extension, 'remember');
    final LeonardTool recall = _tool(extension, 'recall');
    const String original = '  42!?\nsecond line\t— café 東京  ';

    final ToolResult first = await remember.call(<String, Object?>{
      'key': 'confirmation',
      'value': 'replaced',
    });
    final ToolResult stored = await remember.call(<String, Object?>{
      'key': 'confirmation',
      'value': original,
    });
    final ToolResult recalled = await recall.call(<String, Object?>{
      'key': 'confirmation',
    });

    expect(first.ok, isTrue);
    expect(first.value, isEmpty);
    expect(stored.ok, isTrue);
    expect(stored.value, isEmpty);
    expect(recalled.ok, isTrue);
    expect(recalled.value, <String, Object?>{'value': original});
    final Map<String, Object?> recalledValue =
        recalled.value! as Map<String, Object?>;
    expect(
      utf8.encode(recalledValue['value']! as String),
      utf8.encode(original),
    );
    capture.dispose();
  });

  test('core.recall reports target_not_found with the missing key', () async {
    final SemanticsCapture capture = SemanticsCapture();
    final CoreExtension extension = CoreExtension(semantics: capture);

    final ToolResult result = await _tool(
      extension,
      'recall',
    ).call(<String, Object?>{'key': 'missing-key'});

    expect(result.ok, isFalse);
    expect(
      result.error,
      'target_not_found: no remembered value for key "missing-key"',
    );
    capture.dispose();
  });

  test('resetTermination clears remembered values', () async {
    final SemanticsCapture capture = SemanticsCapture();
    final CoreExtension extension = CoreExtension(semantics: capture);
    await _tool(
      extension,
      'remember',
    ).call(<String, Object?>{'key': 'confirmation', 'value': '732901'});
    await _tool(
      extension,
      'done',
    ).call(<String, Object?>{'reason': 'finished'});

    extension.resetTermination();
    final ToolResult recalled = await _tool(
      extension,
      'recall',
    ).call(<String, Object?>{'key': 'confirmation'});

    expect(extension.terminated, isFalse);
    expect(recalled.ok, isFalse);
    expect(
      recalled.error,
      'target_not_found: no remembered value for key "confirmation"',
    );
    capture.dispose();
  });

  test(
    'memory tools reject malformed input and guard termination first',
    () async {
      final SemanticsCapture capture = SemanticsCapture();
      final CoreExtension extension = CoreExtension(semantics: capture);
      final LeonardTool remember = _tool(extension, 'remember');
      final LeonardTool recall = _tool(extension, 'recall');

      expect(remember.inputSchema.raw, const <String, Object?>{
        r'$schema': 'http://json-schema.org/draft-07/schema#',
        'type': 'object',
        'properties': <String, Object?>{
          'key': <String, Object?>{'type': 'string', 'minLength': 1},
          'value': <String, Object?>{'type': 'string', 'minLength': 1},
        },
        'required': <String>['key', 'value'],
        'additionalProperties': false,
      });
      expect(recall.inputSchema.raw, const <String, Object?>{
        r'$schema': 'http://json-schema.org/draft-07/schema#',
        'type': 'object',
        'properties': <String, Object?>{
          'key': <String, Object?>{'type': 'string', 'minLength': 1},
        },
        'required': <String>['key'],
        'additionalProperties': false,
      });

      for (final ({LeonardTool tool, Map<String, Object?> args}) malformed
          in <({LeonardTool tool, Map<String, Object?> args})>[
            (tool: remember, args: <String, Object?>{}),
            (tool: remember, args: <String, Object?>{'key': 1, 'value': 'v'}),
            (tool: remember, args: <String, Object?>{'key': '', 'value': 'v'}),
            (tool: remember, args: <String, Object?>{'key': 'k'}),
            (tool: remember, args: <String, Object?>{'key': 'k', 'value': 1}),
            (tool: remember, args: <String, Object?>{'key': 'k', 'value': ''}),
            (tool: recall, args: <String, Object?>{}),
            (tool: recall, args: <String, Object?>{'key': 1}),
            (tool: recall, args: <String, Object?>{'key': ''}),
          ]) {
        final ToolResult result = await malformed.tool.call(malformed.args);
        expect(
          result.ok,
          isFalse,
          reason: '${malformed.tool.name} ${malformed.args}',
        );
        expect(result.error, startsWith('schema_violation:'));
      }
      expect(
        (await remember.call(<String, Object?>{'key': '', 'value': 'v'})).error,
        'schema_violation: key must be non-empty',
      );
      expect(
        (await remember.call(<String, Object?>{'key': 'k', 'value': ''})).error,
        'schema_violation: value must be non-empty',
      );
      expect(
        (await recall.call(<String, Object?>{'key': ''})).error,
        'schema_violation: key must be non-empty',
      );

      await _tool(
        extension,
        'done',
      ).call(<String, Object?>{'reason': 'finished'});
      for (final LeonardTool tool in <LeonardTool>[remember, recall]) {
        final ToolResult result = await tool.call(<String, Object?>{});
        expect(result.ok, isFalse);
        expect(result.error, startsWith('session_terminated:'));
      }
      capture.dispose();
    },
  );
}

LeonardTool _tool(CoreExtension extension, String name) =>
    extension.tools.firstWhere((LeonardTool tool) => tool.name == name);
