import 'dart:async';
import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;

import '../../prompt/observation_renderer.dart';
import '../action_schema.dart';
import '../frontier/tool_helpers.dart';
import '../model_provider.dart';
import '../types.dart';
import 'model_backend.dart';

/// A [ModelProvider] that drives ANY dartantic `ChatModel` built from a
/// [ModelBackendSpec] (ADR 0003, lenny-4dhv.3).
///
/// This is the seam between lenny's loop and the dartantic backends. It is
/// wire-agnostic: it renders lenny's [ConversationSnapshot] into dartantic
/// [ChatMessage]s + [Tool]s, consumes the [ChatResult] delta stream, and
/// re-asserts lenny's contracts on top — none of which live in the backends:
///
///  * **driver-owned retry** — throws [SchemaRejection] on bad/missing/unknown
///    tool output and lets the loop driver own retry policy;
///  * **runaway-think cap** — aborts a turn that streams more than
///    [runawayThinkCap] chars of reasoning/prose without committing to a tool;
///  * **live thinking** — re-emits reasoning deltas on [thinking()];
///  * **tool namespacing** — encodes dotted tool names (`core.tap`) to the
///    Anthropic-legal wire form and decodes them back;
///  * **structured validation** — validates the chosen tool call against the
///    per-turn [ActionSchema] (the `{action:{tool,args}}` envelope);
///  * **providerRequestId** — captured from the stream's message id.
///
/// A fresh `ChatModel` is built per [decide] call because lenny's tool list
/// changes every turn (extensions activate/deactivate) and dartantic binds
/// tools at construction.
class DartanticModelProvider implements ModelProvider {
  /// Creates a seam over [backend] driving model id [model].
  ///
  /// [capabilities] is supplied by the host (per backend+model). An optional
  /// [client] is forwarded to every per-turn `ChatModel` (used directly on the
  /// swift-infer/Anthropic paths so the driver keeps retry ownership); when
  /// null, each `ChatModel` manages its own. The seam never closes [client].
  DartanticModelProvider({
    required this.backend,
    required this.model,
    required ModelCapabilities capabilities,
    this.client,
    this.runawayThinkCap = 8000,
    ObservationRenderer renderer = const JsonObservationRenderer(),
  }) : _capabilities = capabilities,
       _renderer = renderer;

  /// The backend spec to drive.
  final ModelBackendSpec backend;

  /// The model id (e.g. `qwen3.6-35b-a3b-8bit`, `claude-sonnet-4-0`).
  final String model;

  /// Optional HTTP client forwarded to each per-turn `ChatModel`.
  final http.Client? client;

  /// Abort a turn once this many chars of reasoning/prose stream with no tool
  /// call committed (bounds weak-model rumination; PRD §23 #7).
  final int runawayThinkCap;

  final ModelCapabilities _capabilities;
  final ObservationRenderer _renderer;
  final StreamController<ThinkingDelta> _thinking =
      StreamController<ThinkingDelta>.broadcast();

  @override
  ModelCapabilities get capabilities => _capabilities;

  @override
  Stream<ThinkingDelta> thinking() => _thinking.stream;

  @override
  Future<ModelDecision> decide(
    ConversationSnapshot snapshot,
    ActionSchema schema,
  ) async {
    final tools = [
      for (final t in snapshot.tools)
        Tool(
          name: encodeToolName(t.name),
          description: t.description,
          inputSchema: Schema.fromMap(Map<String, Object?>.from(t.inputSchema)),
          onCall: (args) async => null,
        ),
    ];

    final chatModel = buildBackendChatModel(
      backend,
      model: model,
      tools: tools,
      client: client,
    );

    final rawText = StringBuffer();
    final thinkingBuf = StringBuffer();
    String? wireToolName;
    var toolArgs = const <String, dynamic>{};
    String? providerRequestId;
    var aborted = false;

    try {
      await for (final result in chatModel.sendStream(_toMessages(snapshot))) {
        providerRequestId ??= result.id;
        for (final part in result.output.parts) {
          if (part is ThinkingPart) {
            thinkingBuf.write(part.text);
            if (part.text.isNotEmpty) {
              _thinking.add(ThinkingDelta(text: part.text, isFinal: false));
            }
          } else if (part is TextPart) {
            rawText.write(part.text);
          } else if (part is ToolPart && part.kind == ToolPartKind.call) {
            wireToolName = part.toolName;
            toolArgs = part.arguments ?? const <String, dynamic>{};
          }
        }
        if (wireToolName == null &&
            rawText.length + thinkingBuf.length > runawayThinkCap) {
          aborted = true;
          break;
        }
      }
    } finally {
      chatModel.dispose();
      _thinking.add(const ThinkingDelta(text: '', isFinal: true));
    }

    if (wireToolName == null) {
      throw SchemaRejection(
        validationError: aborted
            ? 'runaway thinking: ${rawText.length + thinkingBuf.length} chars '
                  'with no tool call (aborted before completion)'
            : 'no tool call in response',
        rawOutput: rawText.toString(),
      );
    }

    final descriptor = lookupTool(snapshot.tools, wireToolName);
    if (descriptor == null) {
      throw unknownToolRejection(
        wireToolName,
        snapshot.tools,
        rawPayload: <String, Object?>{'name': wireToolName, 'input': toolArgs},
      );
    }

    // Validate the decoded tool call against the per-turn ActionSchema using
    // the dotted (catalog) tool name — throws SchemaRejection on mismatch.
    final envelope = jsonEncode(<String, dynamic>{
      'action': <String, dynamic>{'tool': descriptor.name, 'args': toolArgs},
    });
    final decoded = schema.validate(envelope);
    final action = decoded['action'] as Map<String, dynamic>;

    return ModelDecision(
      action: (
        tool: action['tool'] as String,
        args: (action['args'] as Map).cast<String, dynamic>(),
      ),
      thinking: thinkingBuf.isEmpty ? null : thinkingBuf.toString(),
      providerRequestId: providerRequestId,
    );
  }

  /// Closes the thinking stream. Does not close a caller-supplied [client].
  void dispose() => _thinking.close();

  /// Renders a [ConversationSnapshot] into dartantic [ChatMessage]s. Mirrors the
  /// hand-rolled providers: a system message, then per turn a user message
  /// (tool_result correlation + observation + diff + optional screenshot) or a
  /// model message (thinking + the tool call). Synthetic `toolu_turn_<n>` call
  /// ids correlate an assistant tool call with the following tool result.
  List<ChatMessage> _toMessages(ConversationSnapshot snapshot) {
    final messages = <ChatMessage>[];
    if (snapshot.systemMessage.isNotEmpty) {
      messages.add(ChatMessage.system(snapshot.systemMessage));
    }

    String? pendingCallId;
    String? pendingToolName;
    var assistantIndex = 0;

    for (final turn in snapshot.turns) {
      switch (turn) {
        case UserTurn():
          final parts = <Part>[];
          if (pendingCallId != null) {
            parts.add(
              ToolPart.result(
                callId: pendingCallId,
                toolName: pendingToolName ?? '',
                result: turn.toolResult != null
                    ? jsonEncode(turn.toolResult)
                    : 'ok',
              ),
            );
            pendingCallId = null;
            pendingToolName = null;
          } else if (turn.toolResult != null) {
            parts.add(TextPart(jsonEncode(turn.toolResult)));
          }
          final obsText = turn.trimmed
              ? '{"trimmed":true}'
              : _renderer.render(turn.observation);
          parts.add(TextPart('Observation:\n$obsText'));
          parts.add(
            TextPart(
              'Diff since last turn:\n${jsonEncode(turn.diff.toJson())}',
            ),
          );
          if (_capabilities.vision && !turn.trimmed) {
            final shot = turn.observation.screenshot;
            if (shot != null && shot.isNotEmpty) {
              parts.add(DataPart(base64Decode(shot), mimeType: 'image/png'));
            }
          }
          messages.add(ChatMessage(role: ChatMessageRole.user, parts: parts));
        case AssistantTurn():
          final callId = 'toolu_turn_$assistantIndex';
          final wireName = encodeToolName(turn.action.tool);
          final parts = <Part>[
            if (turn.thinking.isNotEmpty) ThinkingPart(turn.thinking),
            ToolPart.call(
              callId: callId,
              toolName: wireName,
              arguments: turn.action.args,
            ),
          ];
          messages.add(ChatMessage(role: ChatMessageRole.model, parts: parts));
          pendingCallId = callId;
          pendingToolName = wireName;
          assistantIndex++;
      }
    }
    return messages;
  }
}
