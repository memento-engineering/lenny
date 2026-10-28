import 'dart:convert';

import 'package:http/http.dart' as http;

/// An http client for the Anthropic backend that marks prompt-cache
/// breakpoints on each outgoing messages request (lenny-0bcv; decision
/// `anthropic-prompt-caching-is-set-on-the-wire-by-a-leonard-client`).
///
/// It exists because dartantic's Anthropic chat model exposes no cache control:
/// it renders the system prompt as one string and no block with a
/// `cache_control` member. So this client rewrites the JSON body of a `POST`
/// whose path ends in `/v1/messages`:
///
///  * a non-empty string `system` becomes a list of one text block, and the
///    last non-thinking block of a non-empty `system` is marked;
///  * the message just before the newest user message (the conversation the
///    model has already answered) has its last block that is neither a
///    thinking block nor an empty text block marked;
///  * nothing else is marked: not the newest user message, not the tool
///    definitions, never a thinking block;
///  * marks are added only while the body holds fewer than Anthropic's four
///    `cache_control` members, counting those already on tools, system and
///    messages. A body that adds none is forwarded as the original request.
///
/// Every other request (another path or method, a streamed request, a body
/// that is not a JSON object) is forwarded as the same instance, untouched.
/// A mark is `{"type": "ephemeral"}`.
///
/// It retries nothing (the loop driver owns retry) and closes nothing: the
/// owner of the inner client closes it.
class AnthropicPromptCacheClient extends http.BaseClient {
  /// Wraps [_inner], which every request is sent through exactly once.
  AnthropicPromptCacheClient(this._inner);

  final http.Client _inner;

  /// Anthropic's limit on `cache_control` breakpoints in one request.
  static const _maxBreakpoints = 4;

  static const _thinkingTypes = {'thinking', 'redacted_thinking'};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request is! http.Request ||
        request.method != 'POST' ||
        !request.url.path.endsWith('/v1/messages')) {
      return _inner.send(request);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(request.bodyBytes));
    } on FormatException {
      return _inner.send(request);
    }
    if (decoded is! Map<String, dynamic>) return _inner.send(request);

    final body = decoded;
    var budget = _maxBreakpoints - _existingMarks(body);
    var changed = false;
    if (budget > 0 && _markSystem(body)) {
      changed = true;
      budget--;
    }
    if (budget > 0 && _markPrefix(body)) {
      changed = true;
      budget--;
    }
    if (!changed) return _inner.send(request);

    final rewritten = http.Request(request.method, request.url)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection;
    request.headers.forEach((name, value) {
      if (name.toLowerCase() != 'content-length') {
        rewritten.headers[name] = value;
      }
    });
    // bodyBytes, not body: setting body would rewrite the copied content-type.
    rewritten.bodyBytes = utf8.encode(jsonEncode(body));
    return _inner.send(rewritten);
  }

  /// Closes nothing: whoever opened the inner client closes it.
  @override
  void close() {}

  /// Counts the `cache_control` members already on the tool definitions, the
  /// system blocks and the content blocks of every message.
  static int _existingMarks(Map<String, dynamic> body) {
    var count = 0;
    void countIn(Object? list) {
      if (list is! List<dynamic>) return;
      for (final entry in list) {
        if (entry is Map<String, dynamic> &&
            entry.containsKey('cache_control')) {
          count++;
        }
      }
    }

    countIn(body['tools']);
    countIn(body['system']);
    final messages = body['messages'];
    if (messages is List<dynamic>) {
      for (final message in messages) {
        if (message is Map<String, dynamic>) countIn(message['content']);
      }
    }
    return count;
  }

  /// Marks the last non-thinking system block, turning a string system into
  /// one text block first. Returns whether a mark was added.
  static bool _markSystem(Map<String, dynamic> body) {
    final system = body['system'];
    final List<dynamic> blocks;
    if (system is String && system.isNotEmpty) {
      blocks = <dynamic>[
        <String, dynamic>{'type': 'text', 'text': system},
      ];
    } else if (system is List<dynamic> && system.isNotEmpty) {
      blocks = system;
    } else {
      return false;
    }
    for (var i = blocks.length - 1; i >= 0; i--) {
      final block = blocks[i];
      if (block is! Map<String, dynamic> ||
          _thinkingTypes.contains(block['type'])) {
        continue;
      }
      if (block.containsKey('cache_control')) return false;
      block['cache_control'] = _ephemeral();
      body['system'] = blocks;
      return true;
    }
    return false;
  }

  /// Marks the last markable block of the message just before the newest user
  /// message. Returns whether a mark was added.
  static bool _markPrefix(Map<String, dynamic> body) {
    final messages = body['messages'];
    if (messages is! List<dynamic>) return false;
    var newestUser = -1;
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message is Map<String, dynamic> && message['role'] == 'user') {
        newestUser = i;
        break;
      }
    }
    if (newestUser < 1) return false;
    final target = messages[newestUser - 1];
    if (target is! Map<String, dynamic>) return false;

    final content = target['content'];
    final List<dynamic> blocks;
    if (content is String && content.isNotEmpty) {
      blocks = <dynamic>[
        <String, dynamic>{'type': 'text', 'text': content},
      ];
    } else if (content is List<dynamic>) {
      blocks = content;
    } else {
      return false;
    }
    for (var i = blocks.length - 1; i >= 0; i--) {
      final block = blocks[i];
      if (block is! Map<String, dynamic>) continue;
      final type = block['type'];
      final text = block['text'];
      if (_thinkingTypes.contains(type)) continue;
      if (type == 'text' && (text is! String || text.isEmpty)) continue;
      if (block.containsKey('cache_control')) return false;
      block['cache_control'] = _ephemeral();
      target['content'] = blocks;
      return true;
    }
    return false;
  }

  static Map<String, dynamic> _ephemeral() => <String, dynamic>{
    'type': 'ephemeral',
  };
}
