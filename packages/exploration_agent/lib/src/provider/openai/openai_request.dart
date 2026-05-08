/// Pure request-body builder for OpenAI Chat Completions tools API.
///
/// Web-compatible: pure Dart, no `dart:io`.
library;

import '../action_schema.dart';
import '../frontier/frontier_defaults.dart';
import '../frontier/vision_image.dart';
import '../types.dart';

/// Build the request body for `POST /v1/chat/completions`.
///
/// `prompt.userMessages` entries may contain:
///   - `text` (String) — added as a `{type: 'text', text: ...}` content part
///   - `screenshot` ([VisionImage]) — added as an `{type: 'image_url', ...}`
///     content part using [VisionImage.toOpenAiPart]
///   - any pre-shaped OpenAI content part — passed through verbatim
///
/// When [schemaErrorNote] is non-null a system note is appended instructing
/// the model to retry with a tool_call matching the declared tools (.18's
/// retry-once contract via [SchemaRejection]).
Map<String, dynamic> buildOpenAiRequest({
  required String model,
  required PromptPayload prompt,
  required ActionSchema schema,
  bool stream = false,
  String? schemaErrorNote,
}) {
  // Use schema reference so analyzer doesn't flag it as unused — the schema
  // is part of the public surface so callers can compose it once and pass it
  // into both the request builder and the response parser.
  assert(schema.jsonSchema.isNotEmpty);

  final List<Map<String, dynamic>> messages = <Map<String, dynamic>>[
    <String, dynamic>{'role': 'system', 'content': prompt.systemMessage},
  ];

  if (schemaErrorNote != null) {
    messages.add(<String, dynamic>{
      'role': 'system',
      'content':
          'Previous response failed schema validation: $schemaErrorNote. '
              'Reply with a tool_call matching the declared tools.',
    });
  }

  for (final um in prompt.userMessages) {
    final List<Map<String, dynamic>> parts = <Map<String, dynamic>>[];

    final dynamic text = um['text'];
    if (text is String) {
      parts.add(<String, dynamic>{'type': 'text', 'text': text});
    }

    final dynamic shot = um['screenshot'];
    if (shot is VisionImage) {
      parts.add(shot.toOpenAiPart());
    } else if (um['type'] == 'image_url') {
      // pre-shaped OpenAI image part — passthrough
      parts.add(um);
    }

    if (parts.isEmpty) {
      // Fallback: stringify the whole map so we don't drop content silently.
      parts.add(<String, dynamic>{'type': 'text', 'text': um.toString()});
    }

    messages.add(<String, dynamic>{'role': 'user', 'content': parts});
  }

  final List<Map<String, dynamic>> tools = prompt.tools
      .map((t) => <String, dynamic>{
            'type': 'function',
            'function': <String, dynamic>{
              'name': t.name,
              'description': t.description,
              'parameters': t.inputSchema,
            },
          })
      .toList();

  final Map<String, dynamic> body = <String, dynamic>{
    'model': model,
    'messages': messages,
    'tools': tools,
    'tool_choice': 'required',
    'temperature': FrontierDefaults.temperature,
    'max_completion_tokens': FrontierDefaults.maxTokens,
  };

  if (stream) {
    body['stream'] = true;
  }

  return body;
}
