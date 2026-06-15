import 'dart:convert';

import 'package:json_schema/json_schema.dart';

import '../types.dart';

/// Encode a dotted [ToolDescriptor] name (`core.tap`) into the wire form
/// accepted by Anthropic's tool API (`core_tap`).
///
/// Anthropic tool names match `^[a-zA-Z0-9_-]{1,64}$`.
String encodeToolName(String dotted) => dotted.replaceAll('.', '_');

/// Look up a [ToolDescriptor] by its wire-encoded name (dotted name with
/// `.` replaced by `_`). Returns `null` when no match exists.
ToolDescriptor? lookupTool(List<ToolDescriptor> tools, String wireName) {
  for (final t in tools) {
    if (encodeToolName(t.name) == wireName) return t;
  }
  return null;
}

/// Build the canonical [SchemaRejection] for "model emitted a tool name
/// the prompt did not offer". All frontier providers share this shape
/// so the loop driver and any panel-side observer see the same surface.
///
/// [wireName] is the raw name the model emitted (encoded form for
/// Anthropic / swift-infer, dotted form for OpenAI). [tools] is the
/// prompt's tool list; its encoded names are listed alphabetically in
/// the error message so failures are diffable across turns. [rawPayload]
/// is JSON-encoded into [SchemaRejection.rawOutput] so debuggers can
/// see both the offending name and the args the model tried to pass.
SchemaRejection unknownToolRejection(
  String wireName,
  List<ToolDescriptor> tools, {
  required Map<String, Object?> rawPayload,
}) {
  final available = tools.map((t) => encodeToolName(t.name)).toList()..sort();
  return SchemaRejection(
    validationError:
        'model emitted unknown tool: $wireName; available: [${available.join(', ')}]',
    rawOutput: jsonEncode(rawPayload),
  );
}

/// Validate [args] against [tool.inputSchema] using the same
/// `package:json_schema` draft-07 path as `ActionSchema`.
///
/// Throws [SchemaRejection] on mismatch — the caller (the loop driver)
/// owns retry policy.
void validateToolArgs(ToolDescriptor tool, Map<String, dynamic> args) {
  final result = JsonSchema.create(
    tool.inputSchema,
    schemaVersion: SchemaVersion.draft7,
  ).validate(args);
  if (!result.isValid) {
    throw SchemaRejection(
      validationError: result.errors.map((e) => e.toString()).join('; '),
      rawOutput: args.toString(),
    );
  }
}
