import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../action_schema.dart';
import '../frontier/tool_helpers.dart';
import '../model_provider.dart';
import '../types.dart';
import 'swift_infer_config.dart';

/// `ModelProvider` for the user's swift-infer Swift+MLX gateway.
///
/// Speaks Anthropic-compat (`/v1/messages`) and is essentially the
/// frontier Anthropic provider with a swift-infer base URL plus
/// Qwen3.6-tuned sampling knobs and a config-gated vision capability.
///
/// Streaming: SSE-decodes the response so `<think>...</think>` chunks
/// surface live on [thinking] (PRD §23 #7). Tool calls are accumulated
/// from `input_json_delta` events.
///
/// Web-compatible: pure Dart over `package:http`; no `dart:io`.
///
/// Retry contract: throws [SchemaRejection] on a malformed response;
/// the loop driver (.18) owns retry policy per .14's contract.
class SwiftInferModelProvider implements ModelProvider {
  SwiftInferModelProvider({
    required this.config,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Configuration (base URL, model, sampling, vision gate).
  final SwiftInferConfig config;

  final http.Client _client;
  final StreamController<ThinkingDelta> _thinking =
      StreamController<ThinkingDelta>.broadcast();

  @override
  ModelCapabilities get capabilities => ModelCapabilities(
        vision: config.enableVision,
        preserveThinking: config.preserveThinking,
        maxContext: 128000,
        supportsToolUse: true,
      );

  @override
  Stream<ThinkingDelta> thinking() => _thinking.stream;

  /// Build the outgoing header set.
  ///
  /// Mirrors the wire contract enforced by `fs agent`
  /// (`factoryskills/internal/agent/agent.go`): Bearer auth, SSE accept,
  /// per-conversation/session/capture-bodies trace headers. The
  /// well-known headers always win — `extraHeaders` is merged in first
  /// then overwritten by the well-known set so a misconfigured
  /// `extraHeaders` cannot smuggle in a different `Authorization` or
  /// trace header.
  Map<String, String> _headers() {
    final h = <String, String>{}..addAll(config.extraHeaders);
    h['content-type'] = 'application/json';
    h['accept'] = 'text/event-stream';
    h['anthropic-version'] = '2023-06-01';
    final tok = config.bearerToken;
    if (tok != null && tok.isNotEmpty) {
      h['authorization'] = 'Bearer $tok';
    }
    if (config.captureBodies) {
      h['x-swift-infer-capture-bodies'] = 'true';
    }
    final cid = config.conversationId;
    if (cid != null && cid.isNotEmpty) {
      h['x-conversation-id'] = cid;
    }
    final sid = config.sessionId;
    if (sid != null && sid.isNotEmpty) {
      h['x-session-id'] = sid;
    }
    return h;
  }

  Map<String, dynamic> _buildBody(
    PromptPayload prompt, {
    required bool stream,
  }) {
    final content = config.enableVision
        ? prompt.userMessages
        : prompt.userMessages
            .where((b) => b['type'] != 'image')
            .toList();
    return <String, dynamic>{
      'model': config.model,
      'max_tokens': config.maxTokens,
      'temperature': config.temperature,
      'top_p': config.topP,
      'top_k': config.topK,
      'presence_penalty': config.presencePenalty,
      'repetition_penalty': config.repetitionPenalty,
      'preserve_thinking': config.preserveThinking,
      'stream': stream,
      'system': prompt.systemMessage,
      'tools': prompt.tools
          .map((t) => <String, dynamic>{
                'name': encodeToolName(t.name),
                'description': t.description,
                'input_schema': t.inputSchema,
              })
          .toList(),
      'messages': <Map<String, dynamic>>[
        <String, dynamic>{'role': 'user', 'content': content},
      ],
    };
  }

  @override
  Future<ModelDecision> decide(
    PromptPayload prompt,
    ActionSchema schema,
  ) async {
    final endpoint = config.baseUrl.resolve('/v1/messages');
    final req = http.Request('POST', endpoint)
      ..headers.addAll(_headers())
      ..body = jsonEncode(_buildBody(prompt, stream: true));
    final streamed = await _client.send(req);

    final raw = StringBuffer();
    Map<String, dynamic>? toolUse;
    StringBuffer? inputJsonBuf;
    var inThink = false;

    await for (final line in streamed.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) continue;
      final payload = line.substring(6).trim();
      if (payload.isEmpty || payload == '[DONE]') continue;
      final evt = jsonDecode(payload) as Map<String, dynamic>;
      final type = evt['type'] as String?;
      if (type == 'content_block_start') {
        final block = (evt['content_block'] as Map).cast<String, dynamic>();
        if (block['type'] == 'tool_use') {
          toolUse = block;
          inputJsonBuf = StringBuffer();
        }
      } else if (type == 'content_block_delta') {
        final delta = (evt['delta'] as Map).cast<String, dynamic>();
        final dtype = delta['type'] as String?;
        if (dtype == 'text_delta') {
          final text = delta['text'] as String;
          raw.write(text);
          inThink = _emitThinking(text, inThink: inThink);
        } else if (dtype == 'input_json_delta' && inputJsonBuf != null) {
          inputJsonBuf.write(delta['partial_json'] as String? ?? '');
        }
      }
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
    );
  }

  /// Walk [text] looking for `<think>` / `</think>` boundaries, emitting
  /// [ThinkingDelta] fragments for the contents. Returns the new
  /// inside-think state after consuming this chunk.
  bool _emitThinking(String text, {required bool inThink}) {
    var i = 0;
    var state = inThink;
    while (i < text.length) {
      if (!state) {
        final open = text.indexOf('<think>', i);
        if (open < 0) break;
        i = open + '<think>'.length;
        state = true;
      } else {
        final close = text.indexOf('</think>', i);
        if (close < 0) {
          _thinking.add(ThinkingDelta(
            text: text.substring(i),
            isFinal: false,
          ));
          i = text.length;
        } else {
          if (close > i) {
            _thinking.add(ThinkingDelta(
              text: text.substring(i, close),
              isFinal: false,
            ));
          }
          _thinking.add(const ThinkingDelta(text: '', isFinal: true));
          i = close + '</think>'.length;
          state = false;
        }
      }
    }
    return state;
  }
}
