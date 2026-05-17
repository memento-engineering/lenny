import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../action_schema.dart';
import '../frontier/frontier_defaults.dart';
import '../frontier/thinking_decoder.dart';
import '../frontier/tool_helpers.dart';
import '../model_provider.dart';
import '../types.dart';

/// Set of Claude model ids that accept image inputs (PRD §22).
///
/// Public so a host (e.g. the DevTools panel) can advertise vision
/// support for a model id without instantiating a provider — see
/// `provider/capabilities_lookup.dart`.
const kAnthropicVisionModels = <String>{
  'claude-sonnet-4-6',
  'claude-opus-4-6',
};

/// `ModelProvider` for Claude 4.6+ class models via Anthropic's HTTP
/// tool-use API. Web-compatible: pure HTTP via `package:http`, no
/// `dart:io`.
///
/// Hosts the SHARED frontier helpers (`FrontierDefaults`, `VisionImage`,
/// `validateToolArgs`, `lookupTool`) consumed by the OpenAI provider
/// (.37).
///
/// Streaming: SSE-decodes the response so Anthropic-native
/// `thinking_delta` events surface live on [thinking] via the shared
/// [ThinkingSseDecoder] (cx6.49). Tool calls are accumulated from
/// `input_json_delta` events.
///
/// Retry contract: throws [SchemaRejection] on a malformed response;
/// the loop driver (.18) owns retry policy per .14's contract.
class AnthropicModelProvider implements ModelProvider {
  AnthropicModelProvider({
    required this.model,
    required this.apiKey,
    Uri? endpoint,
    http.Client? client,
  })  : endpoint =
            endpoint ?? Uri.parse('https://api.anthropic.com/v1/messages'),
        _client = client ?? http.Client();

  /// Anthropic model id (e.g. `claude-sonnet-4-6`).
  final String model;

  /// Anthropic API key, sent in the `x-api-key` header.
  final String apiKey;

  /// Messages endpoint — defaults to Anthropic production.
  final Uri endpoint;

  final http.Client _client;
  final StreamController<ThinkingDelta> _thinking =
      StreamController<ThinkingDelta>.broadcast();

  @override
  ModelCapabilities get capabilities => ModelCapabilities(
        vision: kAnthropicVisionModels.contains(model),
        preserveThinking: false,
        maxContext: 200000,
        supportsToolUse: true,
      );

  @override
  Stream<ThinkingDelta> thinking() => _thinking.stream;

  @override
  Future<ModelDecision> decide(
    PromptPayload prompt,
    ActionSchema schema,
  ) async {
    final body = <String, dynamic>{
      'model': model,
      'max_tokens': FrontierDefaults.maxTokens,
      'temperature': FrontierDefaults.temperature,
      'stream': true,
      'system': prompt.systemMessage,
      'tools': prompt.tools
          .map((t) => <String, dynamic>{
                'name': encodeToolName(t.name),
                'description': t.description,
                'input_schema': t.inputSchema,
              })
          .toList(),
      'messages': <Map<String, dynamic>>[
        <String, dynamic>{'role': 'user', 'content': prompt.userMessages},
      ],
    };

    final req = http.Request('POST', endpoint)
      ..headers.addAll(<String, String>{
        'content-type': 'application/json',
        'accept': 'text/event-stream',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      })
      ..body = jsonEncode(body);
    final streamed = await _client.send(req);

    final raw = StringBuffer();
    Map<String, dynamic>? toolUse;
    StringBuffer? inputJsonBuf;
    String? providerRequestId;
    final thinkingDecoder = ThinkingSseDecoder(_thinking);

    try {
      await for (final line in streamed.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (!line.startsWith('data: ')) continue;
        final payload = line.substring(6).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;
        final evt = jsonDecode(payload) as Map<String, dynamic>;
        thinkingDecoder.onEvent(evt);
        final type = evt['type'] as String?;
        if (type == 'message_start') {
          final Map<String, dynamic>? msg =
              (evt['message'] as Map?)?.cast<String, dynamic>();
          final Object? id = msg?['id'];
          if (id is String && id.isNotEmpty) {
            providerRequestId = id;
          }
        } else if (type == 'content_block_start') {
          final block = (evt['content_block'] as Map).cast<String, dynamic>();
          if (block['type'] == 'tool_use') {
            toolUse = block;
            inputJsonBuf = StringBuffer();
          }
        } else if (type == 'content_block_delta') {
          final delta = (evt['delta'] as Map).cast<String, dynamic>();
          final dtype = delta['type'] as String?;
          if (dtype == 'input_json_delta' && inputJsonBuf != null) {
            inputJsonBuf.write(delta['partial_json'] as String? ?? '');
          } else if (dtype == 'text_delta') {
            raw.write(delta['text'] as String? ?? '');
          }
        }
      }
    } finally {
      thinkingDecoder.onDone();
    }

    if (toolUse == null) {
      throw SchemaRejection(
        validationError: 'no tool_use block in response',
        rawOutput: raw.toString(),
      );
    }

    final wireName = toolUse['name'] as String;
    final inputJson = inputJsonBuf?.toString() ?? '';
    final args = inputJson.isEmpty
        ? <String, dynamic>{}
        : (jsonDecode(inputJson) as Map).cast<String, dynamic>();
    final tool = lookupTool(prompt.tools, wireName);
    if (tool == null) {
      throw unknownToolRejection(
        wireName,
        prompt.tools,
        rawPayload: <String, Object?>{'name': wireName, 'input': args},
      );
    }
    final dottedName = tool.name;

    final envelope = jsonEncode(<String, dynamic>{
      'action': <String, dynamic>{'tool': dottedName, 'args': args},
    });
    final validated = schema.validate(envelope);
    final action = (validated['action'] as Map).cast<String, dynamic>();
    return ModelDecision(
      action: (
        tool: action['tool'] as String,
        args: (action['args'] as Map).cast<String, dynamic>(),
      ),
      providerRequestId: providerRequestId,
    );
  }
}
