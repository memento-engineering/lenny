/// Pure request-body builder for OpenAI Chat Completions tools API.
///
/// Web-compatible: pure Dart, no `dart:io`.
library;

import 'dart:convert';

import '../../prompt/observation_renderer.dart';
import '../action_schema.dart';
import '../frontier/frontier_defaults.dart';
import '../frontier/vision_image.dart';
import '../types.dart';

/// Build the request body for `POST /v1/chat/completions` from a
/// [ConversationSnapshot].
///
/// Vision is gated on [visionEnabled] — the provider passes its
/// `capabilities.vision` here so trajectory replay / test injection
/// can't smuggle an image through a vision-blind model.
///
/// Thinking is NOT propagated into history — OpenAI's chat-completions
/// API has no first-class thinking content type, so historical
/// assistant turns are rendered as plain `tool_calls` only.
///
/// When [schemaErrorNote] is non-null a system note is appended instructing
/// the model to retry with a tool_call matching the declared tools (the
/// loop driver's retry-once contract via [SchemaRejection]).
Map<String, dynamic> buildOpenAiRequest({
  required String model,
  required ConversationSnapshot snapshot,
  required ActionSchema schema,
  required bool visionEnabled,
  ObservationRenderer renderer = const JsonObservationRenderer(),
  bool stream = false,
  String? schemaErrorNote,
}) {
  assert(schema.jsonSchema.isNotEmpty);

  final List<Map<String, dynamic>> messages = <Map<String, dynamic>>[
    <String, dynamic>{'role': 'system', 'content': snapshot.systemMessage},
  ];

  if (schemaErrorNote != null) {
    messages.add(<String, dynamic>{
      'role': 'system',
      'content':
          'Previous response failed schema validation: $schemaErrorNote. '
          'Reply with a tool_call matching the declared tools.',
    });
  }

  String? pendingToolCallId;
  int assistantIndex = 0;
  for (final ConversationTurn turn in snapshot.turns) {
    if (turn is UserTurn) {
      if (pendingToolCallId != null) {
        // OpenAI requires a {role:tool} message (not a user content block)
        // to answer a preceding tool_calls entry.
        final String resultContent = turn.toolResult != null
            ? jsonEncode(turn.toolResult)
            : 'ok';
        messages.add(<String, dynamic>{
          'role': 'tool',
          'tool_call_id': pendingToolCallId,
          'content': resultContent,
        });
        pendingToolCallId = null;
      }
      final List<Map<String, dynamic>> parts = <Map<String, dynamic>>[];
      if (turn.toolResult != null && pendingToolCallId == null) {
        // First turn or consecutive retry (no preceding tool_call to pair):
        // render as a text part so schema/validation errors surface.
        parts.add(<String, dynamic>{
          'type': 'text',
          'text': jsonEncode(turn.toolResult),
        });
      }
      final String obsText = turn.trimmed
          ? '{"trimmed":true}'
          : renderer.render(turn.observation);
      parts.add(<String, dynamic>{
        'type': 'text',
        'text': 'Observation:\n$obsText',
      });
      parts.add(<String, dynamic>{
        'type': 'text',
        'text': 'Diff since last turn:\n${jsonEncode(turn.diff.toJson())}',
      });
      final String? shot = turn.observation.screenshot;
      if (!turn.trimmed && visionEnabled && shot != null) {
        parts.add(VisionImage.fromBase64(shot).toOpenAiPart());
      }
      messages.add(<String, dynamic>{'role': 'user', 'content': parts});
    } else if (turn is AssistantTurn) {
      final String callId = 'call_$assistantIndex';
      assistantIndex += 1;
      messages.add(<String, dynamic>{
        'role': 'assistant',
        'tool_calls': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': callId,
            'type': 'function',
            'function': <String, dynamic>{
              'name': turn.action.tool,
              'arguments': jsonEncode(turn.action.args),
            },
          },
        ],
      });
      pendingToolCallId = callId;
    }
  }

  final List<Map<String, dynamic>> tools = snapshot.tools
      .map(
        (ToolDescriptor t) => <String, dynamic>{
          'type': 'function',
          'function': <String, dynamic>{
            'name': t.name,
            'description': t.description,
            'parameters': t.inputSchema,
          },
        },
      )
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
