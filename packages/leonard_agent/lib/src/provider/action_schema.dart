import 'dart:convert';

import 'package:json_schema/json_schema.dart';

import '../json_value.dart';
import 'types.dart';

/// JSON Schema (draft-07) constraining a single model decision.
///
/// Composed fresh on every turn from the merged tool list (PRD §16.2):
/// `action` is a `oneOf` discriminated union over each tool's name and
/// `inputSchema`. Schema-violating output throws [SchemaRejection]; the
/// loop driver retries once per PRD §17.
class ActionSchema {
  ActionSchema._(this.jsonSchema, this._validator);

  /// Reconstructs a transported schema and its draft-07 validator.
  factory ActionSchema.fromJson(Map<String, dynamic> root) => ActionSchema._(
    root,
    JsonSchema.create(root, schemaVersion: SchemaVersion.draft7),
  );

  /// The composed JSON Schema document.
  final Map<String, dynamic> jsonSchema;

  final JsonSchema _validator;

  /// Returns the composed JSON Schema document unchanged.
  Map<String, dynamic> toJson() => jsonSchema;

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
  /// Lossless numeric values are normalized according to the emitted tool's
  /// declared argument schema before validation. The original schema remains
  /// unchanged and all of its constraints are applied to the normalized copy.
  ///
  /// Throws [SchemaRejection] on JSON parse failure or schema violation;
  /// returns the normalized decoded map on success.
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

    final normalized = _normalizeActionEnvelope(decoded);
    final result = _validator.validate(normalized);
    if (!result.isValid) {
      throw SchemaRejection(
        validationError: result.errors.map((e) => e.toString()).join('; '),
        rawOutput: rawOutput,
      );
    }
    return normalized;
  }

  Map<String, dynamic> _normalizeActionEnvelope(Map<String, dynamic> decoded) {
    final normalized = Map<String, dynamic>.from(decoded);
    final action = decoded['action'];
    if (action is! Map<String, dynamic>) return normalized;

    final rootProperties = jsonSchema['properties'];
    if (rootProperties is! Map<String, dynamic>) return normalized;
    final actionSchema = rootProperties['action'];
    if (actionSchema is! Map<String, dynamic>) return normalized;
    final variants = actionSchema['oneOf'];
    if (variants is! List<dynamic>) return normalized;

    final matchingVariants = variants.where((variant) {
      if (variant is! Map<String, dynamic>) return false;
      final properties = variant['properties'];
      if (properties is! Map<String, dynamic>) return false;
      final toolSchema = properties['tool'];
      return toolSchema is Map<String, dynamic> &&
          toolSchema['const'] == action['tool'];
    }).toList();
    if (matchingVariants.length != 1) return normalized;

    final selected = matchingVariants.single as Map<String, dynamic>;
    final selectedProperties = selected['properties'];
    if (selectedProperties is! Map<String, dynamic>) return normalized;
    final argsSchema = selectedProperties['args'];
    if (argsSchema is! Map<String, dynamic>) return normalized;

    final normalizedAction = Map<String, dynamic>.from(action);
    if (action.containsKey('args')) {
      normalizedAction['args'] = _normalizeSchemaValue(
        action['args'],
        argsSchema,
      );
    }
    normalized['action'] = normalizedAction;
    return normalized;
  }

  Object? _normalizeSchemaValue(Object? value, Map<String, dynamic> schema) {
    if (_schemaDeclaresType(schema, 'integer')) {
      return _coerceSchemaInteger(value) ?? value;
    }
    if (_schemaDeclaresType(schema, 'number')) {
      return _coerceSchemaNumber(value) ?? value;
    }

    if (_schemaDeclaresType(schema, 'object') &&
        value is Map<String, dynamic>) {
      final normalized = Map<String, dynamic>.from(value);
      final properties = schema['properties'];
      if (properties is! Map<String, dynamic>) return normalized;

      for (final entry in properties.entries) {
        final propertySchema = entry.value;
        if (value.containsKey(entry.key) &&
            propertySchema is Map<String, dynamic>) {
          normalized[entry.key] = _normalizeSchemaValue(
            value[entry.key],
            propertySchema,
          );
        }
      }
      return normalized;
    }

    if (_schemaDeclaresType(schema, 'array') && value is List<dynamic>) {
      final items = schema['items'];
      if (items is! Map<String, dynamic>) return List<dynamic>.from(value);
      return value
          .map((element) => _normalizeSchemaValue(element, items))
          .toList();
    }

    return value;
  }

  bool _schemaDeclaresType(Map<String, dynamic> schema, String expected) {
    final type = schema['type'];
    return type == expected || type is List<dynamic> && type.contains(expected);
  }

  int? _coerceSchemaInteger(Object? value) {
    if (value is int) return value;
    if (value is double) {
      if (!value.isFinite || value != value.roundToDouble()) return null;
      return value.toInt();
    }
    if (value is! String) return null;

    final trimmed = value.trim();
    final integer = int.tryParse(trimmed);
    if (integer != null) return integer;
    final decimal = double.tryParse(trimmed);
    if (decimal == null ||
        !decimal.isFinite ||
        decimal != decimal.roundToDouble()) {
      return null;
    }
    return decimal.toInt();
  }

  num? _coerceSchemaNumber(Object? value) {
    if (value is num) return value.isFinite ? value : null;
    if (value is! String) return null;

    final number = num.tryParse(value.trim());
    return number != null && number.isFinite ? number : null;
  }

  @override
  bool operator ==(Object other) =>
      other is ActionSchema && jsonValuesEqual(jsonSchema, other.jsonSchema);

  @override
  int get hashCode => jsonValueHash(jsonSchema);
}
