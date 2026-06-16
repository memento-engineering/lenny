import 'dart:async';
import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;

import 'swift_infer_chat_options.dart';

/// A dartantic [ChatModel] that speaks swift-infer's Anthropic-compatible
/// `/v1/messages` wire (ADR 0003, lenny-4dhv.1).
///
/// **Why a custom model instead of dartantic's stock `AnthropicChatModel`:**
///  * swift-infer/Qwen streams thinking content blocks **without** Anthropic's
///    cryptographic `signature`. `anthropic_sdk_dart`'s strict parser hard-casts
///    `signature` as a non-null `String` and throws every turn. This model
///    parses the SSE leniently and never requires a signature.
///  * swift-infer accepts Qwen-tuned sampling knobs (`top_k`,
///    `presence_penalty`, `repetition_penalty`, `preserve_thinking`) that
///    `AnthropicChatOptions` cannot express.
///
/// **Streaming convention** mirrors dartantic's own Anthropic mapper: each
/// emitted [ChatResult]'s `output` is a *delta* [ChatMessage] carrying the
/// incremental part(s) — a [ThinkingPart] for reasoning deltas, a [TextPart] for
/// answer text, and a single [ToolPart.call] emitted at `content_block_stop`
/// once its `input_json` has fully accumulated. `finishReason` rides the
/// `message_delta`. A higher layer (dartantic's `Agent`/accumulator, or lenny's
/// `ModelProvider` seam) consolidates the deltas.
///
/// **swift-infer / Qwen quirk:** reasoning can arrive either as native Anthropic
/// `thinking`/`thinking_delta` blocks OR inlined as `<think>...</think>` markers
/// inside `text_delta`. Both are routed to [ThinkingPart]; the `<think>` scan is
/// stateful across chunks (including markers split across chunk boundaries).
///
/// **Tool names** are passed through verbatim and must match Anthropic's
/// `^[a-zA-Z0-9_-]{1,64}$` (no dots). lenny's dotted tool namespacing
/// (`core.tap`) is encoded/decoded by the `ModelProvider` seam, not here, so this
/// generic model stays backend-agnostic.
///
/// Web-compatible: pure Dart over `package:http`, no `dart:io`. Does **not**
/// retry internally — it uses the supplied client directly, so the caller owns
/// retry/timing (the lenny `SchemaRejection`/runaway-cap policy lives in the
/// seam, not here).
class SwiftInferChatModel extends ChatModel<SwiftInferChatOptions> {
  /// Creates a swift-infer chat model.
  ///
  /// [name] is the MLX model id (e.g. `qwen3.6-35b-a3b-8bit`). [baseUrl] is the
  /// **bare origin** (e.g. `http://localhost:8080`); `/v1/messages` is appended.
  /// [bearerToken] is sent as `Authorization: Bearer <token>` when non-empty.
  /// [headers] are merged first and then overridden by the well-known set
  /// (content-type, accept, anthropic-version, authorization) so the well-known
  /// set always wins — use it for `X-Conversation-Id` / `X-Session-Id` /
  /// `X-Swift-Infer-Capture-Bodies`. A supplied [client] is used directly (no
  /// retry wrapper) and is NOT closed on [dispose]; an internally-created client
  /// is.
  SwiftInferChatModel({
    required super.name,
    required Uri baseUrl,
    super.tools,
    super.temperature,
    String? bearerToken,
    Map<String, String> headers = const {},
    http.Client? client,
    SwiftInferChatOptions? defaultOptions,
  }) : _baseUrl = baseUrl,
       _bearerToken = bearerToken,
       _extraHeaders = headers,
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       super(defaultOptions: defaultOptions ?? const SwiftInferChatOptions());

  final Uri _baseUrl;
  final String? _bearerToken;
  final Map<String, String> _extraHeaders;
  final http.Client _client;
  final bool _ownsClient;

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    SwiftInferChatOptions? options,
    Schema? outputSchema,
  }) async* {
    final opts = options ?? defaultOptions;
    final request = http.Request('POST', _baseUrl.resolve('/v1/messages'))
      ..headers.addAll(_buildHeaders())
      ..body = jsonEncode(_buildBody(messages, opts));

    final streamed = await _client.send(request);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final errBody = await streamed.stream.bytesToString();
      throw SwiftInferHttpException(streamed.statusCode, errBody);
    }

    final decoder = _SseChatDecoder();
    await for (final line
        in streamed.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') continue;
      final Object? decoded;
      try {
        decoded = jsonDecode(payload);
      } on FormatException {
        continue; // tolerate keep-alives / partial non-JSON data lines
      }
      if (decoded is! Map<String, dynamic>) continue;
      yield* decoder.onEvent(decoded);
    }
    // Flush text held back for split-marker detection, and any tool block that
    // never received its content_block_stop (e.g. truncated stream).
    yield* decoder.onDone();
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
  }

  Map<String, String> _buildHeaders() {
    // extraHeaders first, then the well-known set wins on conflict.
    final headers = <String, String>{..._extraHeaders};
    headers['content-type'] = 'application/json';
    headers['accept'] = 'text/event-stream';
    headers['anthropic-version'] = '2023-06-01';
    final token = _bearerToken;
    if (token != null && token.isNotEmpty) {
      headers['authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Map<String, dynamic> _buildBody(
    List<ChatMessage> messages,
    SwiftInferChatOptions opts,
  ) {
    final system = messages
        .where((m) => m.role == ChatMessageRole.system)
        .expand((m) => m.parts.whereType<TextPart>().map((p) => p.text))
        .join('\n');

    final body = <String, dynamic>{
      'model': name,
      'max_tokens': opts.maxTokens,
      'temperature': temperature ?? opts.temperature,
      'top_p': opts.topP,
      'top_k': opts.topK,
      'presence_penalty': opts.presencePenalty,
      'repetition_penalty': opts.repetitionPenalty,
      'preserve_thinking': opts.preserveThinking,
      'stream': true,
      'messages': _buildMessages(messages, opts),
    };
    if (system.isNotEmpty) body['system'] = system;
    final stops = opts.stopSequences;
    if (stops != null && stops.isNotEmpty) body['stop_sequences'] = stops;

    final toolList = tools;
    if (toolList != null && toolList.isNotEmpty) {
      body['tools'] = [
        for (final t in toolList)
          {
            'name': t.name,
            'description': t.description,
            'input_schema': t.inputSchema.value,
          },
      ];
      body['tool_choice'] = {
        'type': opts.toolChoice == SwiftInferToolChoice.any ? 'any' : 'auto',
      };
    }
    return body;
  }

  List<Map<String, dynamic>> _buildMessages(
    List<ChatMessage> messages,
    SwiftInferChatOptions opts,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final m in messages) {
      switch (m.role) {
        case ChatMessageRole.system:
          continue; // carried in body['system']
        case ChatMessageRole.user:
          final content = <Map<String, dynamic>>[];
          // Anthropic requires tool_result blocks first in a user turn; any
          // accompanying text/image follows (do not drop them).
          for (final p in m.parts.whereType<ToolPart>().where(
            (p) => p.kind == ToolPartKind.result,
          )) {
            content.add({
              'type': 'tool_result',
              'tool_use_id': p.callId,
              'content': _serializeResult(p.result),
            });
          }
          for (final p in m.parts) {
            if (p is TextPart) {
              content.add({'type': 'text', 'text': p.text});
            } else if (p is DataPart && p.mimeType.startsWith('image/')) {
              content.add({
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': p.mimeType,
                  'data': base64Encode(p.bytes),
                },
              });
            }
          }
          if (content.isNotEmpty) out.add({'role': 'user', 'content': content});
        case ChatMessageRole.model:
          final content = <Map<String, dynamic>>[];
          // Replay reasoning as a leading <think> text block for continuity
          // (swift-infer's preserve_thinking knob handles the rest).
          if (opts.preserveThinking) {
            final thinking = m.parts
                .whereType<ThinkingPart>()
                .map((p) => p.text)
                .join();
            if (thinking.isNotEmpty) {
              content.add({'type': 'text', 'text': '<think>$thinking</think>'});
            }
          }
          for (final p in m.parts) {
            if (p is TextPart) {
              content.add({'type': 'text', 'text': p.text});
            } else if (p is ToolPart && p.kind == ToolPartKind.call) {
              content.add({
                'type': 'tool_use',
                'id': p.callId,
                'name': p.toolName,
                'input': p.arguments ?? const <String, dynamic>{},
              });
            }
          }
          if (content.isNotEmpty) {
            out.add({'role': 'assistant', 'content': content});
          }
      }
    }
    return out;
  }

  static String _serializeResult(Object? result) =>
      result == null ? 'ok' : (result is String ? result : jsonEncode(result));
}

/// Thrown when swift-infer returns a non-2xx HTTP status. The seam maps this to
/// a failed turn; it is distinct from a schema/validation rejection.
class SwiftInferHttpException implements Exception {
  /// Creates an exception carrying the [statusCode] and response [body].
  SwiftInferHttpException(this.statusCode, this.body);

  /// The HTTP status code (>= 400).
  final int statusCode;

  /// The raw response body, for diagnostics.
  final String body;

  @override
  String toString() => 'SwiftInferHttpException($statusCode): $body';
}

/// Stateful decoder mapping swift-infer's Anthropic-compatible SSE event JSON
/// into delta [ChatResult]s, mirroring dartantic's
/// `MessageStreamEventTransformer` semantics without the strict SDK parse.
class _SseChatDecoder {
  static const _openTag = '<think>';
  static const _closeTag = '</think>';

  String? _messageId;
  int? _inputTokens;
  final Map<int, String> _toolIdByIndex = {};
  final Map<int, String> _toolNameByIndex = {};
  final Map<int, StringBuffer> _toolArgsByIndex = {};
  final Map<int, Map<String, dynamic>> _toolSeedArgsByIndex = {};

  /// Most recently opened tool-block index — used to route a tool delta that
  /// arrives without an `index` (lenient; Anthropic always sends one).
  int? _openToolIndex;

  /// Whether we are mid-`<think>` while scanning `text_delta` across chunks.
  bool _inThink = false;

  /// Trailing text held back because it might be a `<think>`/`</think>` marker
  /// split across the chunk boundary.
  String _pendingText = '';

  Stream<ChatResult<ChatMessage>> onEvent(Map<String, dynamic> evt) async* {
    switch (evt['type'] as String?) {
      case 'message_start':
        final message = evt['message'];
        if (message is Map) {
          final id = message['id'];
          if (id is String && id.isNotEmpty) _messageId = id;
          final usage = message['usage'];
          if (usage is Map && usage['input_tokens'] is int) {
            _inputTokens = usage['input_tokens'] as int;
          }
        }
      case 'content_block_start':
        final index = _indexOf(evt);
        final block = evt['content_block'];
        if (block is Map && block['type'] == 'tool_use') {
          _toolIdByIndex[index] = (block['id'] as String?) ?? 'toolu_$index';
          _toolNameByIndex[index] = (block['name'] as String?) ?? '';
          _toolArgsByIndex[index] = StringBuffer();
          _openToolIndex = index;
          final input = block['input'];
          if (input is Map && input.isNotEmpty) {
            _toolSeedArgsByIndex[index] = Map<String, dynamic>.from(input);
          }
        }
      case 'content_block_delta':
        final delta = evt['delta'];
        if (delta is! Map) return;
        switch (delta['type'] as String?) {
          case 'thinking_delta':
            final text = delta['thinking'] as String? ?? '';
            if (text.isNotEmpty) yield _thinkingChunk(text);
          case 'text_delta':
            final text = delta['text'] as String? ?? '';
            if (text.isNotEmpty) yield* _scanText(text);
          case 'input_json_delta':
            final index = _toolIndexFor(evt);
            final buf = index == null ? null : _toolArgsByIndex[index];
            if (buf != null) {
              final partial = delta['partial_json'] as String? ?? '';
              if (partial.isNotEmpty) {
                buf.write(partial);
                _toolSeedArgsByIndex.remove(index); // prefer real streamed args
              }
            }
        }
      case 'content_block_stop':
        yield* _flushTool(_toolIndexFor(evt) ?? _indexOf(evt));
      case 'message_delta':
        final delta = evt['delta'];
        final stopReason = delta is Map
            ? delta['stop_reason'] as String?
            : null;
        final usage = evt['usage'];
        final outputTokens = usage is Map && usage['output_tokens'] is int
            ? usage['output_tokens'] as int
            : null;
        yield _finishChunk(_mapFinishReason(stopReason), outputTokens);
      case 'message_stop':
      case 'ping':
      default:
        break;
    }
  }

  /// Flushes any text held back for split-marker detection and any tool block
  /// that never received a `content_block_stop` (e.g. truncated stream).
  Stream<ChatResult<ChatMessage>> onDone() async* {
    if (_pendingText.isNotEmpty) {
      final text = _pendingText;
      _pendingText = '';
      yield _inThink ? _thinkingChunk(text) : _textChunk(text);
    }
    for (final index in _toolIdByIndex.keys.toList()) {
      yield* _flushTool(index);
    }
  }

  Stream<ChatResult<ChatMessage>> _flushTool(int index) async* {
    final toolId = _toolIdByIndex.remove(index);
    final toolName = _toolNameByIndex.remove(index);
    final argsBuf = _toolArgsByIndex.remove(index);
    final seed = _toolSeedArgsByIndex.remove(index);
    if (_openToolIndex == index) _openToolIndex = null;
    if (toolId != null) {
      yield _toolChunk(
        toolId,
        toolName ?? '',
        _parseArgs(argsBuf?.toString() ?? '', seed),
      );
    }
  }

  /// The tool index for a tool-related event, falling back to the single open
  /// tool block when the server omits `index`.
  int? _toolIndexFor(Map<String, dynamic> evt) {
    final raw = evt['index'];
    return raw is num ? raw.toInt() : _openToolIndex;
  }

  int _indexOf(Map<String, dynamic> evt) =>
      (evt['index'] as num?)?.toInt() ?? 0;

  /// Decodes accumulated tool args, degrading to [seed] (or `{}`) on malformed
  /// or truncated JSON rather than tearing down the stream — the seam's schema
  /// validation then surfaces a clean rejection.
  Map<String, dynamic> _parseArgs(String argsJson, Map<String, dynamic>? seed) {
    if (argsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(argsJson);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } on FormatException {
        // fall through to seed/empty
      }
    }
    return seed ?? <String, dynamic>{};
  }

  /// Splits `text_delta` into `<think>`-wrapped (→ [ThinkingPart]) and plain
  /// (→ [TextPart]) segments, carrying `_inThink` AND a partial-marker tail
  /// across chunk boundaries.
  Stream<ChatResult<ChatMessage>> _scanText(String chunk) async* {
    var rest = _pendingText + chunk;
    _pendingText = '';
    while (rest.isNotEmpty) {
      if (_inThink) {
        final close = rest.indexOf(_closeTag);
        if (close < 0) {
          final safe = _safeEmitLen(rest, _closeTag);
          if (safe > 0) yield _thinkingChunk(rest.substring(0, safe));
          _pendingText = rest.substring(safe);
          return;
        }
        if (close > 0) yield _thinkingChunk(rest.substring(0, close));
        _inThink = false;
        rest = rest.substring(close + _closeTag.length);
      } else {
        final open = rest.indexOf(_openTag);
        if (open < 0) {
          final safe = _safeEmitLen(rest, _openTag);
          if (safe > 0) yield _textChunk(rest.substring(0, safe));
          _pendingText = rest.substring(safe);
          return;
        }
        if (open > 0) yield _textChunk(rest.substring(0, open));
        _inThink = true;
        rest = rest.substring(open + _openTag.length);
      }
    }
  }

  /// Returns how much of [s] is safe to emit without risking a [tag] split
  /// across the boundary: holds back the longest suffix of [s] that is a proper
  /// prefix of [tag].
  int _safeEmitLen(String s, String tag) {
    final maxHold = s.length < tag.length - 1 ? s.length : tag.length - 1;
    for (var hold = maxHold; hold > 0; hold--) {
      if (tag.startsWith(s.substring(s.length - hold))) return s.length - hold;
    }
    return s.length;
  }

  ChatResult<ChatMessage> _thinkingChunk(String text) =>
      _delta([ThinkingPart(text)]);

  ChatResult<ChatMessage> _textChunk(String text) => _delta([TextPart(text)]);

  ChatResult<ChatMessage> _toolChunk(
    String id,
    String name,
    Map<String, dynamic> args,
  ) => _delta([ToolPart.call(callId: id, toolName: name, arguments: args)]);

  ChatResult<ChatMessage> _delta(List<Part> parts) => ChatResult<ChatMessage>(
    id: _messageId,
    output: ChatMessage(role: ChatMessageRole.model, parts: parts),
    messages: const [],
  );

  ChatResult<ChatMessage> _finishChunk(
    FinishReason reason,
    int? outputTokens,
  ) => ChatResult<ChatMessage>(
    id: _messageId,
    output: ChatMessage(role: ChatMessageRole.model, parts: const []),
    messages: const [],
    finishReason: reason,
    usage: (_inputTokens != null || outputTokens != null)
        ? LanguageModelUsage(
            promptTokens: _inputTokens,
            responseTokens: outputTokens,
            totalTokens: (_inputTokens != null && outputTokens != null)
                ? _inputTokens! + outputTokens
                : null,
          )
        : null,
  );
}

FinishReason _mapFinishReason(String? stopReason) => switch (stopReason) {
  'end_turn' => FinishReason.stop,
  'stop_sequence' => FinishReason.stop,
  'tool_use' => FinishReason.toolCalls,
  'max_tokens' => FinishReason.length,
  _ => FinishReason.unspecified,
};
