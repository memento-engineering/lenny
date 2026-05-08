import 'package:json_schema/json_schema.dart';

import '../types.dart';

/// Encode a dotted [ToolDescriptor] name (`core.tap`) into the wire form
/// accepted by Anthropic's tool API (`core_tap`).
///
/// Anthropic tool names match `^[a-zA-Z0-9_-]{1,64}$`.
String encodeToolName(String dotted) => dotted.replaceAll('.', '_');

/// Reverse [encodeToolName] using [tools] as the lookup; returns the
/// original [wire] string when no match exists.
String decodeToolName(String wire, List<ToolDescriptor> tools) =>
    lookupTool(tools, wire)?.name ?? wire;

/// Look up a [ToolDescriptor] by its wire-encoded name (dotted name with
/// `.` replaced by `_`). Returns `null` when no match exists.
ToolDescriptor? lookupTool(List<ToolDescriptor> tools, String wireName) {
  for (final t in tools) {
    if (encodeToolName(t.name) == wireName) return t;
  }
  return null;
}

/// Validate [args] against [tool.inputSchema] using the same
/// `package:json_schema` draft-07 path as `ActionSchema`.
///
/// Throws [SchemaRejection] on mismatch — the caller (loop driver, .18)
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
