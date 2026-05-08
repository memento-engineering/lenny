import 'dart:convert';

import 'package:http/http.dart' as http;

import '../action_schema.dart';
import '../frontier/frontier_defaults.dart';
import '../frontier/tool_helpers.dart';
import '../model_provider.dart';
import '../types.dart';

/// Set of Claude model ids that accept image inputs (PRD §22).
const _visionModels = {'claude-sonnet-4-6', 'claude-opus-4-6'};

/// `ModelProvider` for Claude 4.6+ class models via Anthropic's HTTP
/// tool-use API. Web-compatible: pure HTTP via `package:http`, no
/// `dart:io`.
///
/// Hosts the SHARED frontier helpers (`FrontierDefaults`, `VisionImage`,
/// `validateToolArgs`, `lookupTool`) consumed by the OpenAI provider
/// (.37).
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

  @override
  ModelCapabilities get capabilities => ModelCapabilities(
        vision: _visionModels.contains(model),
        preserveThinking: false,
        maxContext: 200000,
        supportsToolUse: true,
      );

  @override
  Stream<ThinkingDelta> thinking() => const Stream.empty();

  @override
  Future<ModelDecision> decide(
    PromptPayload prompt,
    ActionSchema schema,
  ) async {
    final body = <String, dynamic>{
      'model': model,
      'max_tokens': FrontierDefaults.maxTokens,
      'temperature': FrontierDefaults.temperature,
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

    final resp = await _client.post(
      endpoint,
      headers: <String, String>{
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode(body),
    );

    final raw = resp.body;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final content = (decoded['content'] as List?) ?? const [];

    Map<String, dynamic>? toolUse;
    for (final block in content) {
      if (block is Map && block['type'] == 'tool_use') {
        toolUse = block.cast<String, dynamic>();
        break;
      }
    }
    if (toolUse == null) {
      throw SchemaRejection(
        validationError: 'no tool_use block in response',
        rawOutput: raw,
      );
    }

    final wireName = toolUse['name'] as String;
    final args = (toolUse['input'] as Map).cast<String, dynamic>();
    final dottedName = lookupTool(prompt.tools, wireName)?.name ?? wireName;

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
    );
  }
}
