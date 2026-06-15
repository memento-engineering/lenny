/// Pure response parser for OpenAI Chat Completions tools API.
///
/// Web-compatible: no `dart:io`.
library;

import 'dart:convert';

import '../action_schema.dart';
import '../frontier/tool_helpers.dart';
import '../types.dart';

/// Parse a decoded `/v1/chat/completions` response body into a
/// [ModelDecision].
///
/// Throws [SchemaRejection] when the response shape is malformed (no
/// choices, no tool_calls, unparseable arguments) or when the chosen tool
/// or its arguments fail schema validation. The loop driver (.18) owns
/// retry policy.
ModelDecision parseOpenAiResponse(
  Map<String, dynamic> body, {
  required ActionSchema schema,
  required List<ToolDescriptor> tools,
}) {
  final dynamic choicesRaw = body['choices'];
  if (choicesRaw is! List || choicesRaw.isEmpty) {
    throw SchemaRejection(
      validationError: 'no choices',
      rawOutput: jsonEncode(body),
    );
  }
  final Map<String, dynamic> message =
      ((choicesRaw.first as Map)['message'] as Map).cast<String, dynamic>();

  final dynamic toolCallsRaw = message['tool_calls'];
  if (toolCallsRaw is! List || toolCallsRaw.isEmpty) {
    throw SchemaRejection(
      validationError: 'no tool_calls',
      rawOutput: jsonEncode(body),
    );
  }

  final Map<String, dynamic> firstCall =
      (toolCallsRaw.first as Map).cast<String, dynamic>();
  final Map<String, dynamic> fn =
      (firstCall['function'] as Map).cast<String, dynamic>();
  final String name = fn['name'] as String;
  final String rawArgs = fn['arguments'] as String;

  Map<String, dynamic> args;
  try {
    final dynamic decoded = jsonDecode(rawArgs);
    if (decoded is! Map) {
      throw SchemaRejection(
        validationError: 'tool arguments are not a JSON object',
        rawOutput: rawArgs,
      );
    }
    args = decoded.cast<String, dynamic>();
  } on FormatException catch (e) {
    throw SchemaRejection(
      validationError: 'bad arg JSON: ${e.message}',
      rawOutput: rawArgs,
    );
  }

  // OpenAI returns tool names verbatim — match dotted name directly first,
  // falling back to the wire-encoded form for symmetry with [lookupTool].
  ToolDescriptor? tool;
  for (final t in tools) {
    if (t.name == name) {
      tool = t;
      break;
    }
  }
  tool ??= lookupTool(tools, name);
  if (tool == null) {
    throw unknownToolRejection(
      name,
      tools,
      rawPayload: <String, Object?>{'name': name, 'arguments': args},
    );
  }

  validateToolArgs(tool, args);

  // Validate the composed envelope against the global ActionSchema so the
  // returned decision matches .14's contract end-to-end.
  final String envelope = jsonEncode(<String, dynamic>{
    'action': <String, dynamic>{'tool': tool.name, 'args': args},
  });
  final Map<String, dynamic> validated = schema.validate(envelope);
  final Map<String, dynamic> action =
      (validated['action'] as Map).cast<String, dynamic>();

  // Optional sibling JSON content carrying decision metadata.
  String? rationale;
  String? waitStrategy;
  final dynamic content = message['content'];
  if (content is String && content.isNotEmpty) {
    try {
      final dynamic parsed = jsonDecode(content);
      if (parsed is Map) {
        final m = parsed.cast<String, dynamic>();
        final dynamic r = m['rationale'];
        if (r is String) rationale = r;
        final dynamic w = m['wait_strategy'];
        if (w is String) waitStrategy = w;
      }
    } on FormatException {
      // Non-JSON content is silently ignored per spec.
    }
  }

  return ModelDecision(
    action: (
      tool: action['tool'] as String,
      args: (action['args'] as Map).cast<String, dynamic>(),
    ),
    rationale: rationale,
    waitStrategy: waitStrategy,
  );
}
