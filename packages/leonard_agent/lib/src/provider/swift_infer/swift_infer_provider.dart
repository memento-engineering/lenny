import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../prompt/observation_renderer.dart';
import '../action_schema.dart';
import '../frontier/thinking_decoder.dart';
import '../frontier/tool_helpers.dart';
import '../frontier/vision_image.dart';
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
/// the loop driver owns retry policy per the ModelProvider contract.
class SwiftInferModelProvider implements ModelProvider {
  SwiftInferModelProvider({required this.config, http.Client? client})
    : _client = client ?? http.Client();

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

  /// Renderer used to flatten an [Observation] into the text of a
  /// user-role message. Constant default.
  static const ObservationRenderer _renderer = JsonObservationRenderer();

  /// Abort a response once this many characters of non-tool text (i.e.
  /// reasoning / prose) have streamed with no `tool_use` block opened.
  /// Weaker models (qwen) sometimes ruminate to `max_tokens` without ever
  /// committing to a tool call; this bounds that "vomit" and surfaces the
  /// existing no-tool_use [SchemaRejection] so the loop retries with a
  /// fresh sample. Healthy turns emit <~2k chars of thinking before the
  /// tool_use; observed runaways exceed ~13k. 8000 sits clear of both.
  static const int _kRunawayThinkCap = 8000;

  /// Build the multi-turn `messages` array for the swift-infer Anthropic-
  /// compat endpoint. Vision is gated on [SwiftInferConfig.enableVision]
  /// per spec — the host-side capability check is re-asserted
  /// at the provider so trajectory replay / test injection can't smuggle
  /// an image through a vision-disabled config.
  List<Map<String, dynamic>> _buildMessages(ConversationSnapshot snapshot) {
    final List<Map<String, dynamic>> messages = <Map<String, dynamic>>[];
    String? pendingToolUseId;
    int assistantIndex = 0;
    for (final ConversationTurn turn in snapshot.turns) {
      if (turn is UserTurn) {
        final List<Map<String, dynamic>> content = <Map<String, dynamic>>[];
        if (pendingToolUseId != null) {
          final String resultContent = turn.toolResult != null
              ? jsonEncode(turn.toolResult)
              : 'ok';
          content.add(<String, dynamic>{
            'type': 'tool_result',
            'tool_use_id': pendingToolUseId,
            'content': resultContent,
          });
          pendingToolUseId = null;
        } else if (turn.toolResult != null) {
          content.add(<String, dynamic>{
            'type': 'text',
            'text': jsonEncode(turn.toolResult),
          });
        }
        final String obsText = turn.trimmed
            ? '{"trimmed":true}'
            : _renderer.render(turn.observation);
        content.add(<String, dynamic>{
          'type': 'text',
          'text': 'Observation:\n$obsText',
        });
        content.add(<String, dynamic>{
          'type': 'text',
          'text': 'Diff since last turn:\n${jsonEncode(turn.diff.toJson())}',
        });
        final String? shot = turn.observation.screenshot;
        if (!turn.trimmed && config.enableVision && shot != null) {
          content.add(VisionImage.fromBase64(shot).toAnthropicBlock());
        }
        messages.add(<String, dynamic>{'role': 'user', 'content': content});
      } else if (turn is AssistantTurn) {
        final List<Map<String, dynamic>> content = <Map<String, dynamic>>[];
        if (turn.thinking.isNotEmpty) {
          content.add(<String, dynamic>{
            'type': 'text',
            'text': '<think>${turn.thinking}</think>',
          });
        }
        final String toolUseId = 'toolu_turn_$assistantIndex';
        assistantIndex += 1;
        content.add(<String, dynamic>{
          'type': 'tool_use',
          'id': toolUseId,
          'name': encodeToolName(turn.action.tool),
          'input': turn.action.args,
        });
        pendingToolUseId = toolUseId;
        messages.add(<String, dynamic>{
          'role': 'assistant',
          'content': content,
        });
      }
    }
    return messages;
  }

  @override
  Future<ModelDecision> decide(
    ConversationSnapshot snapshot,
    ActionSchema schema,
  ) async {
    final body = <String, dynamic>{
      'model': config.model,
      'max_tokens': config.maxTokens,
      'temperature': config.temperature,
      'top_p': config.topP,
      'top_k': config.topK,
      'presence_penalty': config.presencePenalty,
      'repetition_penalty': config.repetitionPenalty,
      'preserve_thinking': config.preserveThinking,
      'stream': true,
      'system': snapshot.systemMessage,
      'tools': snapshot.tools
          .map(
            (ToolDescriptor t) => <String, dynamic>{
              'name': encodeToolName(t.name),
              'description': t.description,
              'input_schema': t.inputSchema,
            },
          )
          .toList(),
      // Force a tool call every turn — parity with the Anthropic provider
      // (anthropic_provider.dart sends the same). Without it the gateway
      // lets the model answer with prose, which surfaces here as a
      // "no tool_use block" SchemaRejection and a wasted turn (weaker
      // models like qwen do this often).
      'tool_choice': const <String, dynamic>{'type': 'any'},
      'messages': _buildMessages(snapshot),
    };
    final endpoint = config.baseUrl.resolve('/v1/messages');
    final req = http.Request('POST', endpoint)
      ..headers.addAll(_headers())
      ..body = jsonEncode(body);
    final streamed = await _client.send(req);

    final raw = StringBuffer();
    Map<String, dynamic>? toolUse;
    StringBuffer? inputJsonBuf;
    String? providerRequestId;
    var inThink = false;
    final thinkingDecoder = ThinkingSseDecoder(_thinking);
    final StringBuffer thinkingText = StringBuffer();

    try {
      await for (final line
          in streamed.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (!line.startsWith('data: ')) continue;
        final payload = line.substring(6).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;
        final evt = jsonDecode(payload) as Map<String, dynamic>;
        thinkingDecoder.onEvent(evt);
        final type = evt['type'] as String?;
        if (type == 'message_start') {
          final Map<String, dynamic>? msg = (evt['message'] as Map?)
              ?.cast<String, dynamic>();
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
          if (dtype == 'text_delta') {
            final text = delta['text'] as String;
            raw.write(text);
            inThink = _emitThinking(text, inThink: inThink);
            inThink = _accumulateThinking(
              text,
              inThink: inThink,
              sink: thinkingText,
            );
            if (toolUse == null && raw.length > _kRunawayThinkCap) {
              // Runaway: streaming reasoning/prose with no tool_use block in
              // sight. Stop reading instead of letting it run to max_tokens;
              // the no-tool_use SchemaRejection below triggers a retry (a
              // fresh sample at temperature usually does not re-runaway).
              break;
            }
          } else if (dtype == 'input_json_delta' && inputJsonBuf != null) {
            inputJsonBuf.write(delta['partial_json'] as String? ?? '');
          }
        }
      }
    } finally {
      thinkingDecoder.onDone();
    }

    if (toolUse == null) {
      throw SchemaRejection(
        validationError: raw.length > _kRunawayThinkCap
            ? 'runaway thinking: ${raw.length} chars with no tool_use block '
                  '(aborted before max_tokens)'
            : 'no tool_use block in response',
        rawOutput: raw.toString(),
      );
    }

    final wireName = toolUse['name'] as String;
    final inputJson = inputJsonBuf?.toString() ?? '';
    final args = inputJson.isEmpty
        ? <String, dynamic>{}
        : (jsonDecode(inputJson) as Map).cast<String, dynamic>();
    final tool = lookupTool(snapshot.tools, wireName);
    if (tool == null) {
      throw unknownToolRejection(
        wireName,
        snapshot.tools,
        rawPayload: <String, Object?>{'name': wireName, 'input': args},
      );
    }
    final dottedName = tool.name;

    final envelope = jsonEncode(<String, dynamic>{
      'action': <String, dynamic>{'tool': dottedName, 'args': args},
    });
    final validated = schema.validate(envelope);
    final action = (validated['action'] as Map).cast<String, dynamic>();
    final String thinking = thinkingText.toString();
    return ModelDecision(
      action: (
        tool: action['tool'] as String,
        args: (action['args'] as Map).cast<String, dynamic>(),
      ),
      thinking: thinking.isEmpty ? null : thinking,
      providerRequestId: providerRequestId,
    );
  }

  /// Same `<think>` boundary walk as [_emitThinking], but writes to a
  /// passed-in [sink] instead of the live stream — used by
  /// [decideForConversation] to capture full thinking text for
  /// carry-forward into the next [AssistantTurn].
  bool _accumulateThinking(
    String text, {
    required bool inThink,
    required StringBuffer sink,
  }) {
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
          sink.write(text.substring(i));
          i = text.length;
        } else {
          if (close > i) sink.write(text.substring(i, close));
          i = close + '</think>'.length;
          state = false;
        }
      }
    }
    return state;
  }

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
          _thinking.add(ThinkingDelta(text: text.substring(i), isFinal: false));
          i = text.length;
        } else {
          if (close > i) {
            _thinking.add(
              ThinkingDelta(text: text.substring(i, close), isFinal: false),
            );
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
