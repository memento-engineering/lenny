// Pins the Anthropic prompt-cache rewrite (lenny-0bcv): which blocks of a
// messages request carry a `cache_control` breakpoint, what passes through
// untouched, that the client retries and closes nothing, and that the
// dartantic provider sends every Anthropic turn through it.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:leonard_agent/src/observation/diff_models.dart';
import 'package:leonard_agent/src/observation/models.dart';
import 'package:leonard_agent/src/provider/action_schema.dart';
import 'package:leonard_agent/src/provider/backend/anthropic_prompt_cache_client.dart';
import 'package:leonard_agent/src/provider/backend/dartantic_model_provider.dart';
import 'package:leonard_agent/src/provider/backend/model_backend.dart';
import 'package:leonard_agent/src/provider/types.dart';
import 'package:test/test.dart';

const _ephemeral = {'type': 'ephemeral'};

/// Records every request it is sent and answers a benign SSE stream.
class _RecordingClient extends http.BaseClient {
  _RecordingClient({this.toThrow});

  final Object? toThrow;
  final requests = <http.BaseRequest>[];
  var sendCount = 0;
  var closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sendCount++;
    requests.add(request);
    final error = toThrow;
    if (error != null) throw error;
    return http.StreamedResponse(
      Stream.value(utf8.encode('data: [DONE]\n\n')),
      200,
    );
  }

  @override
  void close() => closed = true;
}

http.Request _request(
  String method,
  String path, {
  List<int>? bodyBytes,
  Object? json,
}) {
  final request =
      http.Request(method, Uri.parse('https://api.anthropic.com$path'))
        ..headers.addAll({
          'content-type': 'application/json',
          'x-api-key': 'k',
          'anthropic-version': '2023-06-01',
        });
  if (bodyBytes != null) request.bodyBytes = bodyBytes;
  if (json != null) request.bodyBytes = utf8.encode(jsonEncode(json));
  return request;
}

/// Counts every `cache_control` key anywhere in [value].
int _marks(Object? value) => switch (value) {
  Map<String, dynamic>() => value.entries.fold(
    value.containsKey('cache_control') ? 1 : 0,
    (n, e) => n + _marks(e.value),
  ),
  List<dynamic>() => value.fold(0, (n, e) => n + _marks(e)),
  _ => 0,
};

Map<String, dynamic> _decode(http.BaseRequest request) =>
    jsonDecode((request as http.Request).body) as Map<String, dynamic>;

/// Sends [body] through a cache client and returns what reached the inner
/// client, checking the four-breakpoint limit on every rewrite.
Future<Map<String, dynamic>> _rewrite(Map<String, dynamic> body) async {
  final inner = _RecordingClient();
  await AnthropicPromptCacheClient(
    inner,
  ).send(_request('POST', '/v1/messages', json: body));
  final sent = _decode(inner.requests.single);
  expect(_marks(sent), lessThanOrEqualTo(4));
  return sent;
}

Map<String, dynamic> _user(String text) => {
  'role': 'user',
  'content': [
    {'type': 'text', 'text': text},
  ],
};

Map<String, dynamic> _assistant(List<Map<String, dynamic>> content) => {
  'role': 'assistant',
  'content': content,
};

const _toolUse = {
  'type': 'tool_use',
  'id': 'toolu_turn_0',
  'name': 'core__tap',
  'input': {'node_id': 8},
};

List<Map<String, dynamic>> _tools({int marked = 0}) => [
  for (var i = 0; i < 4; i++)
    {
      'name': 'tool_$i',
      'description': 'tool $i',
      'input_schema': {'type': 'object'},
      if (i < marked) 'cache_control': _ephemeral,
    },
];

Map<String, dynamic> _threeMessages({Object? system = 'be an agent'}) => {
  'model': 'claude-sonnet-4-6',
  'max_tokens': 1024,
  'stream': true,
  if (system != null) 'system': system,
  'tools': _tools(),
  'messages': [
    _user('obs 0'),
    _assistant([
      {'type': 'thinking', 'thinking': 'tap it', 'signature': 's'},
      _toolUse,
    ]),
    {
      'role': 'user',
      'content': [
        {'type': 'tool_result', 'tool_use_id': 'toolu_turn_0', 'content': 'ok'},
      ],
    },
  ],
};

List<dynamic> _messages(Map<String, dynamic> body) =>
    body['messages'] as List<dynamic>;

List<dynamic> _content(Map<String, dynamic> body, int index) =>
    (_messages(body)[index] as Map<String, dynamic>)['content']
        as List<dynamic>;

/// Captures every request body a provider sends and answers a benign SSE
/// stream, so decide() can finish (or throw: only the request is asserted).
class _CapturingClient extends http.BaseClient {
  final bodies = <String>[];
  var closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) bodies.add(request.body);
    return http.StreamedResponse(
      Stream.value(utf8.encode('data: [DONE]\n\n')),
      200,
    );
  }

  @override
  void close() => closed = true;
}

Observation _observation(int id) => Observation.fromJson(<String, dynamic>{
  'semantics': <Map<String, dynamic>>[
    {
      'id': id,
      'role': 'button',
      'label': 'node $id',
      'actions': <String>['tap'],
      'rect': <int>[0, 0, 100, 40],
    },
  ],
  'routes': <String>['home'],
});

const _tapTool = ToolDescriptor(
  name: 'core.tap',
  description: 'tap a node',
  inputSchema: {
    'type': 'object',
    'properties': {
      'node_id': {'type': 'integer'},
    },
    'required': ['node_id'],
    'additionalProperties': false,
  },
);

ConversationSnapshot _oneTurnSnapshot() => ConversationSnapshot(
  systemMessage: 'you are an agent driving an app',
  turns: <ConversationTurn>[
    UserTurn(observation: _observation(8), diff: ObservationDiff.empty()),
  ],
  tools: const <ToolDescriptor>[_tapTool],
);

ConversationSnapshot _threeTurnSnapshot() => ConversationSnapshot(
  systemMessage: 'you are an agent driving an app',
  turns: <ConversationTurn>[
    UserTurn(observation: _observation(8), diff: ObservationDiff.empty()),
    const AssistantTurn(
      thinking: 'tapping settings',
      action: (tool: 'core.tap', args: {'node_id': 8}),
    ),
    UserTurn(
      observation: _observation(9),
      diff: ObservationDiff.empty(),
      toolResult: const {'ok': true},
    ),
  ],
  tools: const <ToolDescriptor>[_tapTool],
);

const _caps = ModelCapabilities(
  vision: false,
  preserveThinking: true,
  maxContext: 128000,
  supportsToolUse: true,
);

const _anthropic = AnthropicBackend(apiKey: 'k');
final _swiftInfer = SwiftInferBackend(
  baseUrl: Uri.parse('http://localhost:8080'),
);

DartanticModelProvider _provider(
  ModelBackendSpec backend, {
  http.Client? client,
}) => DartanticModelProvider(
  backend: backend,
  model: backend is AnthropicBackend ? 'claude-sonnet-4-6' : 'qwen',
  capabilities: _caps,
  client: client,
);

Future<void> _decide(
  DartanticModelProvider provider,
  ConversationSnapshot snapshot,
) async {
  try {
    await provider.decide(snapshot, ActionSchema.fromToolList(snapshot.tools));
  } on Object {
    // decide() may throw on the canned response; only the request matters.
  }
}

/// Asserts [raw] carries a marked list system and, when [prefix], a mark on
/// the last block of `messages[1]` and none elsewhere in `messages`.
void _expectBreakpoints(String raw, {required bool prefix}) {
  final body = jsonDecode(raw) as Map<String, dynamic>;
  final system = body['system'] as List<dynamic>;
  expect((system.last as Map)['cache_control'], _ephemeral);
  if (prefix) {
    expect((_content(body, 1).last as Map)['cache_control'], _ephemeral);
    expect(_marks(_messages(body)), 1);
  } else {
    expect(_marks(_messages(body)), 0);
  }
}

void main() {
  group('AnthropicPromptCacheClient', () {
    test('a string system becomes one marked text block', () async {
      final sent = await _rewrite(_threeMessages());
      expect(sent['system'], [
        {'type': 'text', 'text': 'be an agent', 'cache_control': _ephemeral},
      ]);
    });

    test('a two-block system list is marked on its last block only', () async {
      final sent = await _rewrite(
        _threeMessages(
          system: [
            {'type': 'text', 'text': 'one'},
            {'type': 'text', 'text': 'two'},
          ],
        ),
      );
      expect(sent['system'], [
        {'type': 'text', 'text': 'one'},
        {'type': 'text', 'text': 'two', 'cache_control': _ephemeral},
      ]);
    });

    test('the last block before the newest user message is marked, '
        'and no other message block', () async {
      final sent = await _rewrite(_threeMessages());
      final prefix = _content(sent, 1);
      expect((prefix.last as Map)['cache_control'], _ephemeral);
      expect(_marks(prefix.first), 0);
      expect(_marks(_messages(sent)[0]), 0);
      expect(_marks(_messages(sent)[2]), 0);
      expect(_marks(_messages(sent)), 1);
    });

    test('a string content on the prefix message becomes one marked text '
        'block', () async {
      final body = _threeMessages();
      _messages(body)[1] = {'role': 'assistant', 'content': 'I tapped it'};
      final sent = await _rewrite(body);
      expect(_content(sent, 1), [
        {'type': 'text', 'text': 'I tapped it', 'cache_control': _ephemeral},
      ]);
    });

    test('a one-message body marks only the system', () async {
      final sent = await _rewrite({
        'model': 'claude-sonnet-4-6',
        'system': 'be an agent',
        'messages': [_user('obs 0')],
      });
      expect(
        (sent['system'] as List).single,
        containsPair('cache_control', _ephemeral),
      );
      expect(_marks(_messages(sent)), 0);
      expect(_marks(sent), 1);
    });

    test('a body with no system gets no system member and only the prefix '
        'mark', () async {
      final body = _threeMessages(system: null);
      expect(body.containsKey('system'), isFalse);
      final sent = await _rewrite(body);
      expect(sent.containsKey('system'), isFalse);
      expect((_content(sent, 1).last as Map)['cache_control'], _ephemeral);
      expect(_marks(sent), 1);
    });

    test('an empty system is left as it was and gets no mark', () async {
      for (final empty in <Object>['', <Object>[]]) {
        final sent = await _rewrite(_threeMessages(system: empty));
        expect(sent['system'], empty);
        expect(_marks(sent), 1);
      }
    });

    test('three marks already on the tools give exactly one more, on the '
        'system', () async {
      final body = _threeMessages()..['tools'] = _tools(marked: 3);
      final sent = await _rewrite(body);
      expect(_marks(sent), 4);
      expect(
        (sent['system'] as List).single,
        containsPair('cache_control', _ephemeral),
      );
      expect(_marks(_messages(sent)), 0);
    });

    test('four marks already present forward the identical request', () async {
      final inner = _RecordingClient();
      final body = _threeMessages()..['tools'] = _tools(marked: 4);
      final request = _request('POST', '/v1/messages', json: body);
      final bytes = List<int>.of(request.bodyBytes);
      await AnthropicPromptCacheClient(inner).send(request);
      expect(inner.requests.single, same(request));
      expect((inner.requests.single as http.Request).bodyBytes, bytes);
    });

    test('tool definitions are untouched by a rewrite', () async {
      for (final marked in [0, 3]) {
        final body = _threeMessages()..['tools'] = _tools(marked: marked);
        final tools = jsonDecode(jsonEncode(body['tools']));
        final sent = await _rewrite(body);
        expect(sent['tools'], equals(tools));
      }
    });

    test(
      'a prefix message ending in thinking is marked on its tool_use',
      () async {
        for (final thinking in [
          {'type': 'thinking', 'thinking': 'hm', 'signature': 's'},
          {'type': 'redacted_thinking', 'data': 'xyz'},
        ]) {
          final body = _threeMessages();
          _messages(body)[1] = _assistant([_toolUse, thinking]);
          final sent = await _rewrite(body);
          final prefix = _content(sent, 1);
          expect((prefix.first as Map)['cache_control'], _ephemeral);
          expect((prefix.last as Map).containsKey('cache_control'), isFalse);
        }
      },
    );

    test('a prefix message of only thinking blocks is unmarked, and the '
        'system is still marked', () async {
      final body = _threeMessages();
      _messages(body)[1] = _assistant([
        {'type': 'thinking', 'thinking': 'hm', 'signature': 's'},
        {'type': 'redacted_thinking', 'data': 'xyz'},
      ]);
      final sent = await _rewrite(body);
      expect(_marks(_messages(sent)), 0);
      expect(
        (sent['system'] as List).single,
        containsPair('cache_control', _ephemeral),
      );
    });

    test(
      'other requests pass through as the same instance, byte for byte',
      () async {
        final requests = [
          _request('GET', '/v1/models'),
          _request('POST', '/v1/messages/count_tokens', json: _threeMessages()),
          _request('POST', '/v1/complete', json: _threeMessages()),
          _request(
            'POST',
            '/v1/messages',
            bodyBytes: utf8.encode('not json {'),
          ),
          _request('POST', '/v1/messages', json: [_threeMessages()]),
        ];
        for (final request in requests) {
          final inner = _RecordingClient();
          final bytes = List<int>.of(request.bodyBytes);
          await AnthropicPromptCacheClient(inner).send(request);
          expect(
            inner.requests.single,
            same(request),
            reason: '${request.url}',
          );
          expect((inner.requests.single as http.Request).bodyBytes, bytes);
        }
      },
    );

    test('a rewrite keeps method, url, settings and headers', () async {
      final inner = _RecordingClient();
      final request = _request('POST', '/v1/messages', json: _threeMessages())
        ..followRedirects = false
        ..maxRedirects = 2
        ..persistentConnection = false;
      await AnthropicPromptCacheClient(inner).send(request);
      final sent = inner.requests.single;
      expect(sent, isA<http.Request>());
      expect(sent, isNot(same(request)));
      expect(sent.method, 'POST');
      expect(sent.url, request.url);
      expect(sent.followRedirects, isFalse);
      expect(sent.maxRedirects, 2);
      expect(sent.persistentConnection, isFalse);
      expect(sent.headers['content-type'], 'application/json');
      expect(sent.headers['x-api-key'], 'k');
      expect(sent.headers['anthropic-version'], '2023-06-01');
      expect(sent.contentLength, (sent as http.Request).bodyBytes.length);
      expect(_marks(_decode(sent)), 2);
    });

    test('an inner failure reaches the caller once, without retry', () async {
      final failure = http.ClientException('boom');
      final inner = _RecordingClient(toThrow: failure);
      await expectLater(
        AnthropicPromptCacheClient(
          inner,
        ).send(_request('POST', '/v1/messages', json: _threeMessages())),
        throwsA(same(failure)),
      );
      expect(inner.sendCount, 1);
    });

    test('close leaves the inner client open', () {
      final inner = _RecordingClient();
      AnthropicPromptCacheClient(inner).close();
      expect(inner.closed, isFalse);
    });
  });

  group('DartanticModelProvider prompt caching', () {
    test('an Anthropic turn marks the system and the prefix', () async {
      final fake = _CapturingClient();
      final provider = _provider(_anthropic, client: fake);
      await _decide(provider, _threeTurnSnapshot());
      _expectBreakpoints(fake.bodies.single, prefix: true);
      provider.dispose();
    });

    test('a one-turn Anthropic conversation marks only the system', () async {
      final fake = _CapturingClient();
      final provider = _provider(_anthropic, client: fake);
      await _decide(provider, _oneTurnSnapshot());
      _expectBreakpoints(fake.bodies.single, prefix: false);
      provider.dispose();
    });

    test('a swift-infer turn is sent without breakpoints', () async {
      final fake = _CapturingClient();
      final provider = _provider(_swiftInfer, client: fake);
      await _decide(provider, _threeTurnSnapshot());
      final raw = fake.bodies.single;
      expect(
        (jsonDecode(raw) as Map<String, dynamic>)['system'],
        isA<String>(),
      );
      expect(raw, isNot(contains('cache_control')));
      provider.dispose();
    });

    test('with no client, an Anthropic provider opens one, caches every turn '
        'through it and closes it on dispose', () async {
      final fake = _CapturingClient();
      var factoryCalls = 0;
      final provider = _provider(_anthropic);
      await http.runWithClient(
        () async {
          await _decide(provider, _oneTurnSnapshot());
          await _decide(provider, _threeTurnSnapshot());
        },
        () {
          factoryCalls++;
          return fake;
        },
      );
      expect(factoryCalls, 1);
      expect(fake.bodies, hasLength(2));
      _expectBreakpoints(fake.bodies[0], prefix: false);
      _expectBreakpoints(fake.bodies[1], prefix: true);
      expect(fake.closed, isFalse);
      provider.dispose();
      expect(fake.closed, isTrue);
    });

    test('a supplied client is never closed by dispose', () async {
      for (final backend in <ModelBackendSpec>[_anthropic, _swiftInfer]) {
        final fake = _CapturingClient();
        final provider = _provider(backend, client: fake);
        await _decide(provider, _threeTurnSnapshot());
        provider.dispose();
        expect(fake.closed, isFalse, reason: '$backend');
      }
    });
  });
}
