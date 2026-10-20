// csells/dartantic#119: Claude models newer than 4.6 reject the budgeted
// thinking request dartantic sends, so the Anthropic backend turns thinking off
// for them.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:leonard_agent/src/observation/diff_models.dart';
import 'package:leonard_agent/src/observation/models.dart';
import 'package:leonard_agent/src/provider/action_schema.dart';
import 'package:leonard_agent/src/provider/backend/dartantic_model_provider.dart';
import 'package:leonard_agent/src/provider/backend/model_backend.dart';
import 'package:leonard_agent/src/provider/types.dart';
import 'package:test/test.dart';

/// Answers one Anthropic stream with a `core_tap` call, keeping the request.
/// [gap] spaces the events out in time, as a real stream does.
class _RecordingClient extends http.BaseClient {
  _RecordingClient({this.gap = Duration.zero});

  final Duration gap;
  Map<String, dynamic>? body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) {
      body = jsonDecode(request.body) as Map<String, dynamic>;
    }
    String frame(String name, Map<String, dynamic> data) =>
        'event: $name\ndata: ${jsonEncode(data)}\n\n';
    final List<String> frames = <String>[
      frame('message_start', {
        'type': 'message_start',
        'message': {
          'id': 'msg_t',
          'type': 'message',
          'role': 'assistant',
          'model': 'm',
          'content': <Object>[],
          'stop_reason': null,
          'stop_sequence': null,
          'usage': {'input_tokens': 10, 'output_tokens': 1},
        },
      }),
      frame('content_block_start', {
        'type': 'content_block_start',
        'index': 0,
        'content_block': {
          'type': 'tool_use',
          'id': 'tu1',
          'name': 'core_tap',
          'input': <String, dynamic>{},
        },
      }),
      frame('content_block_delta', {
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'input_json_delta', 'partial_json': '{"nodeId":1}'},
      }),
      frame('content_block_stop', {'type': 'content_block_stop', 'index': 0}),
      frame('message_delta', {
        'type': 'message_delta',
        'delta': {'stop_reason': 'tool_use', 'stop_sequence': null},
        'usage': {'output_tokens': 5},
      }),
      frame('message_stop', {'type': 'message_stop'}),
    ];
    Stream<List<int>> paced() async* {
      for (final String f in frames) {
        yield utf8.encode(f);
        await Future<void>.delayed(gap);
      }
    }

    return http.StreamedResponse(
      paced(),
      200,
      headers: const {'content-type': 'text/event-stream'},
    );
  }
}

const _tap = ToolDescriptor(
  name: 'core.tap',
  description: 'tap a node',
  inputSchema: {
    'type': 'object',
    'properties': {
      'nodeId': {'type': 'integer'},
    },
    'required': ['nodeId'],
    'additionalProperties': false,
  },
);

Future<Map<String, dynamic>> _requestFor(String model) async =>
    (await _decide(model)).$1;

Future<(Map<String, dynamic>, ModelDecision)> _decide(
  String model, {
  Duration gap = Duration.zero,
}) async {
  final client = _RecordingClient(gap: gap);
  final provider = DartanticModelProvider(
    backend: const AnthropicBackend(apiKey: 'k'),
    model: model,
    capabilities: const ModelCapabilities(
      vision: false,
      preserveThinking: false,
      maxContext: 200000,
      supportsToolUse: true,
    ),
    client: client,
  );
  final ModelDecision decision = await provider.decide(
    ConversationSnapshot(
      systemMessage: 'sys',
      turns: [
        UserTurn(
          observation: Observation.empty(),
          diff: ObservationDiff.empty(),
        ),
      ],
      tools: const [_tap],
    ),
    ActionSchema.fromToolList(const [_tap]),
  );
  provider.dispose();
  return (client.body!, decision);
}

void main() {
  test('budgeted thinking is accepted only through Claude 4.6', () {
    // Measured against each id with thinking.type enabled, 2026-10-20.
    const Map<String, bool> measured = <String, bool>{
      'claude-sonnet-4-6': true,
      'claude-opus-4-6': true,
      'claude-opus-4-5-20251101': true,
      'claude-haiku-4-5-20251001': true,
      'claude-sonnet-4-5-20250929': true,
      'claude-opus-4-7': false,
      'claude-opus-4-8': false,
      'claude-opus-5': false,
      'claude-sonnet-5': false,
      'claude-fable-5': false,
      'claude-haiku-5-5': false,
      'claude-sonnet-5-5': false,
      'claude-opus-5-5': false,
      'claude-fable-5-1': false,
    };
    for (final MapEntry<String, bool> e in measured.entries) {
      expect(anthropicAcceptsBudgetThinking(e.key), e.value, reason: e.key);
    }
    // Older names: Sonnet 4.0 (dated, no minor) and the pre-4 version-first
    // form. An unrecognised id is treated as newer.
    expect(anthropicAcceptsBudgetThinking('claude-sonnet-4-20250514'), isTrue);
    expect(
      anthropicAcceptsBudgetThinking('claude-3-7-sonnet-20250219'),
      isTrue,
    );
    expect(anthropicAcceptsBudgetThinking('claude-next'), isFalse);
  });

  test('a 5.x model asks for no thinking, tool_choice still auto', () async {
    // claude-sonnet-5-5 rejects a forced tool_choice as well (measured live).
    final Map<String, dynamic> body = await _requestFor('claude-sonnet-5-5');
    expect(body['thinking'], anyOf(isNull, {'type': 'disabled'}));
    expect(body['tool_choice'], containsPair('type', 'auto'));
  });

  test('Claude 4.6 keeps budgeted thinking and tool_choice auto', () async {
    final Map<String, dynamic> body = await _requestFor('claude-sonnet-4-6');
    expect(body['thinking'], containsPair('type', 'enabled'));
    expect(body['tool_choice'], containsPair('type', 'auto'));
  });

  test(
    'time to first token marks the first event, not the tool call',
    () async {
      // Live on claude-sonnet-5-5 the tool call, the only part, arrived as its
      // block closed; stamping there reported ~2000 output tokens per second.
      final (_, ModelDecision decision) = await _decide(
        'claude-sonnet-5-5',
        gap: const Duration(milliseconds: 60),
      );
      final int ttft = decision.usage!.timeToFirstTokenMs!;
      // message_start is the first of six frames 60 ms apart; the tool call
      // completes ~240 ms in.
      expect(ttft, lessThan(120));
    },
  );
}
