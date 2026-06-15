import 'dart:convert';

import 'package:json_schema/json_schema.dart';

import 'types.dart';

/// JSON Schema (draft-07) constraining a single model decision.
///
/// Composed fresh on every turn from the merged tool list (PRD §16.2):
/// `action` is a `oneOf` discriminated union over each tool's name and
/// `inputSchema`. Schema-violating output throws [SchemaRejection]; the
/// loop driver (.18) retries once per PRD §17.
class ActionSchema {
  ActionSchema._(this.jsonSchema, this._validator);

  /// The composed JSON Schema document.
  final Map<String, dynamic> jsonSchema;

  final JsonSchema _validator;

  /// Compose a fresh schema from the merged tool list.
  ///
  /// Per PRD §16.2 this MUST be invoked every turn — there is
  /// intentionally no memoization, since the tool list can change as
  /// extensions activate or deactivate.
  factory ActionSchema.fromToolList(List<ToolDescriptor> tools) {
    Map<String, dynamic> variant(ToolDescriptor t) => <String, dynamic>{
      'type': 'object',
      'required': <String>['tool', 'args'],
      'properties': <String, dynamic>{
        'tool': <String, dynamic>{'type': 'string', 'const': t.name},
        'args': t.inputSchema,
      },
      'additionalProperties': false,
    };

    final root = <String, dynamic>{
      r'$schema': 'http://json-schema.org/draft-07/schema#',
      'type': 'object',
      'required': <String>['action'],
      'properties': <String, dynamic>{
        'action': <String, dynamic>{'oneOf': tools.map(variant).toList()},
        'rationale': <String, dynamic>{
          'type': <String>['string', 'null'],
        },
        'wait_strategy': <String, dynamic>{
          'type': <String>['string', 'null'],
        },
      },
      'additionalProperties': false,
    };

    return ActionSchema._(
      root,
      JsonSchema.create(root, schemaVersion: SchemaVersion.draft7),
    );
  }

  /// Decode and validate a raw model output against this schema.
  ///
  /// Throws [SchemaRejection] on JSON parse failure or schema violation;
  /// returns the decoded map on success.
  Map<String, dynamic> validate(String rawOutput) {
    Map<String, dynamic> decoded;
    try {
      final parsed = jsonDecode(rawOutput);
      if (parsed is! Map<String, dynamic>) {
        throw SchemaRejection(
          validationError: 'output is not a JSON object',
          rawOutput: rawOutput,
        );
      }
      decoded = parsed;
    } on FormatException catch (e) {
      throw SchemaRejection(
        validationError: 'output is not valid JSON: ${e.message}',
        rawOutput: rawOutput,
      );
    }

    final result = _validator.validate(decoded);
    if (!result.isValid) {
      throw SchemaRejection(
        validationError: result.errors.map((e) => e.toString()).join('; '),
        rawOutput: rawOutput,
      );
    }
    return decoded;
  }
}
