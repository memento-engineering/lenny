import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../prompt/observation_renderer.dart';
import '../action_schema.dart';
import '../frontier/frontier_defaults.dart';
import '../frontier/thinking_decoder.dart';
import '../frontier/tool_helpers.dart';
import '../frontier/vision_image.dart';
import '../model_provider.dart';
import '../types.dart';

/// Set of Claude model ids that accept image inputs (PRD §22).
///
/// Public so a host (e.g. the DevTools panel) can advertise vision
/// support for a model id without instantiating a provider — see
/// `provider/capabilities_lookup.dart`.
const kAnthropicVisionModels = <String>{'claude-sonnet-4-6', 'claude-opus-4-6'};

/// `ModelProvider` for Claude 4.6+ class models via Anthropic's HTTP
/// tool-use API. Web-compatible: pure HTTP via `package:http`, no
/// `dart:io`.
///
/// Hosts the SHARED frontier helpers (`FrontierDefaults`, `VisionImage`,
/// `validateToolArgs`, `lookupTool`) consumed by the OpenAI provider.
///
/// Streaming: SSE-decodes the response so Anthropic-native
/// `thinking_delta` events surface live on [thinking] via the shared
/// [ThinkingSseDecoder]. Tool calls are accumulated from
/// `input_json_delta` events.
///
/// Retry contract: throws [SchemaRejection] on a malformed response;
/// the loop driver owns retry policy per the ModelProvider contract.
class AnthropicModelProvider implements ModelProvider {
  AnthropicModelProvider({
    required this.model,
    required this.apiKey,
    Uri? endpoint,
    http.Client? client,
    void Function(Map<String, Object?> diagnostics)? onCallDiagnostics,
  }) : endpoint =
           endpoint ?? Uri.parse('https://api.anthropic.com/v1/messages'),
       _client = client ?? http.Client(),
       _onCallDiagnostics = onCallDiagnostics;

  /// Anthropic model id (e.g. `claude-sonnet-4-6`).
  final String model;

  /// Anthropic API key, sent in the `x-api-key` header.
  final String apiKey;

  /// Messages endpoint — defaults to Anthropic production.
  final Uri endpoint;

  final http.Client _client;

  /// Optional sink for per-call API diagnostics. Invoked exactly once
  /// per [decide] HTTP call — on success AND on failure — with a
  /// structured map: `duration_ms`, `http_status`, `stop_reason`,
  /// `tool_use`, `ok`, and `error` (when failed). Lets a host log API
  /// health so an outage is visible in run output, not inferred.
  final void Function(Map<String, Object?> diagnostics)? _onCallDiagnostics;

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

  /// Renderer used to flatten an [Observation] into the text of a
  /// user-role message. Constant default; future bead can make this
  /// configurable if alternative renderings emerge.
  static const ObservationRenderer _renderer = JsonObservationRenderer();

  @override
  Future<ModelDecision> decide(
    ConversationSnapshot snapshot,
    ActionSchema schema,
  ) async {
    final List<Map<String, dynamic>> messages = <Map<String, dynamic>>[];
    String? pendingToolUseId;
    int assistantIndex = 0;
    for (final ConversationTurn turn in snapshot.turns) {
      if (turn is UserTurn) {
        final List<Map<String, dynamic>> content = <Map<String, dynamic>>[];
        if (pendingToolUseId != null) {
          // Emit the mandatory tool_result that pairs with the preceding
          // assistant tool_use block.  Anthropic requires this immediately
          // after an assistant message that contained a tool_use block.
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
          // First turn or consecutive retry turn: no preceding tool_use.
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
        // Vision gate (defensive — host gate is upstream; provider
        // re-checks capability so trajectory-replay or test injection
        // can't smuggle an image through a vision-blind model).
        final String? shot = turn.observation.screenshot;
        if (!turn.trimmed && capabilities.vision && shot != null) {
          content.add(VisionImage.fromBase64(shot).toAnthropicBlock());
        }
        messages.add(<String, dynamic>{'role': 'user', 'content': content});
      } else if (turn is AssistantTurn) {
        final List<Map<String, dynamic>> content = <Map<String, dynamic>>[];
        // Drop historical thinking blocks: Anthropic requires a cryptographic
        // signature on thinking content blocks; unsigned blocks cause HTTP 400.
        // When signature carry-forward is implemented, revisit this guard.
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

    final body = <String, dynamic>{
      'model': model,
      'max_tokens': FrontierDefaults.maxTokens,
      'temperature': FrontierDefaults.temperature,
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
      'tool_choice': const <String, dynamic>{'type': 'any'},
      'messages': messages,
    };

    final req = http.Request('POST', endpoint)
      ..headers.addAll(<String, String>{
        'content-type': 'application/json',
        'accept': 'text/event-stream',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        // When the exploration loop runs inside the DevTools **web** build, this
        // POST is a browser fetch; api.anthropic.com blocks cross-origin browser
        // requests by default (CORS preflight has no Access-Control-Allow-Origin).
        // This opt-in header makes Anthropic answer the preflight. No-op on
        // native (CLI) runs. It ships the key to the browser — the durable fix
        // is to run provider HTTP app-side over the VM service.
        'anthropic-dangerous-direct-browser-access': 'true',
      })
      ..body = jsonEncode(body);

    final Stopwatch stopwatch = Stopwatch()..start();
    int? httpStatus;
    String? stopReason;
    Map<String, dynamic>? toolUse;
    String? providerRequestId;
    Object? failure;
    final StringBuffer thinkingText = StringBuffer();
    try {
      final streamed = await _client.send(req);
      httpStatus = streamed.statusCode;

      final raw = StringBuffer();
      StringBuffer? inputJsonBuf;
      final thinkingDecoder = ThinkingSseDecoder(_thinking);
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
            if (dtype == 'input_json_delta' && inputJsonBuf != null) {
              inputJsonBuf.write(delta['partial_json'] as String? ?? '');
            } else if (dtype == 'text_delta') {
              raw.write(delta['text'] as String? ?? '');
            } else if (dtype == 'thinking_delta') {
              thinkingText.write(delta['thinking'] as String? ?? '');
            }
          } else if (type == 'message_delta') {
            final delta = (evt['delta'] as Map?)?.cast<String, dynamic>();
            final Object? sr = delta?['stop_reason'];
            if (sr is String) stopReason = sr;
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
    } catch (e) {
      failure = e;
      rethrow;
    } finally {
      stopwatch.stop();
      _onCallDiagnostics?.call(<String, Object?>{
        'provider': 'anthropic',
        'model': model,
        'duration_ms': stopwatch.elapsedMilliseconds,
        'http_status': httpStatus,
        'stop_reason': stopReason,
        'tool_use': toolUse != null,
        'provider_request_id': providerRequestId,
        'ok': failure == null,
        if (failure != null) 'error': failure.toString(),
      });
    }
  }
}
