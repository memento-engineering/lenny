/// [ModelProvider] backed by any ACP-compatible coding agent.
///
/// PHASE 1 — the agent is used as a one-shot decision oracle: tools are
/// suppressed client-side (see [DenyAllAcpClient]) and the decision comes back
/// as JSON in prose, validated by [ActionSchema] exactly like every other
/// provider. `supportsToolUse` is therefore FALSE — Leonard's tool list goes
/// in as text, not as a native tool schema.
///
/// PHASE 2, if the phase-1 [SchemaRejection] rate warrants it: hand the tool
/// list to the agent's model as a real MCP server via `session/new`'s
/// `mcpServers`, with a capture-only handler that records the call and
/// executes nothing — so `LoopDriver`'s validate → act → notify → persist
/// ordering still runs. See [AcpSession.newSession].
///
/// PRIOR ART: the org has decision-complete design for this seam —
/// `the_grid/docs/SCRATCH-third-party-harnesses.md` D-4 ("structured channels
/// are the PREFERRED transport ... ACP adapter FIRST") and its unfiled bead
/// B-2, whose home is power_station `grid_assets`. This package is a leonard-
/// side early proof of B-2's core claim, not a competing implementation.
///
/// Distinct from `federated_grid_assets`' `acp_envelope.dart`, which borrows
/// ACP's JSON-RPC envelope for the federation bus and deliberately does NOT
/// use the agent-session methods this file is built on. Same protocol family,
/// two method surfaces — the SCRATCH doc rules the shared codec "a precedent,
/// not a dependency", so nothing is imported across.
library;

import 'dart:async';
import 'dart:convert';

import 'package:leonard_agent/leonard_agent.dart';

import 'acp_session.dart';

/// Conservative defaults — an ACP agent does not advertise a context window.
const ModelCapabilities kAcpDefaultCapabilities = ModelCapabilities(
  vision: false,
  preserveThinking: false,
  maxContext: 128000,
  supportsToolUse: false,
);

/// Drives an ACP agent as a per-turn decision oracle.
class AcpModelProvider implements ModelProvider {
  AcpModelProvider({
    required AcpSession session,
    ModelCapabilities capabilities = kAcpDefaultCapabilities,
    ObservationRenderer? renderer,
  }) : _session = session,
       _capabilities = capabilities,
       _renderer = renderer ?? JsonObservationRenderer();

  final AcpSession _session;
  final ModelCapabilities _capabilities;
  final ObservationRenderer _renderer;

  /// The system message + tool list + schema are sent once, on the first
  /// turn. The ACP session carries them forward, so later turns send only
  /// the newest observation — re-sending the whole snapshot every turn would
  /// double-count history the agent already has.
  bool _primed = false;

  @override
  ModelCapabilities get capabilities => _capabilities;

  @override
  Stream<ThinkingDelta> thinking() => _session.thoughts.map(
    (String text) => ThinkingDelta(text: text, isFinal: false),
  );

  @override
  Future<ModelDecision> decide(
    ConversationSnapshot snapshot,
    ActionSchema schema,
  ) async {
    final String prompt = _primed
        ? _renderNewestTurn(snapshot)
        : _renderPriming(snapshot, schema);
    _primed = true;

    final AcpTurn turn = await _session.prompt(prompt);

    // A refused permission means the agent tried to DO something instead of
    // answering. Surface it in the rejection so the operator sees the real
    // cause rather than a bare parse failure.
    if (turn.text.trim().isEmpty) {
      throw SchemaRejection(
        validationError: turn.deniedTools.isEmpty
            ? 'agent returned no text (stopReason: ${turn.stopReason.name})'
            : 'agent attempted tool use instead of answering '
                  '(refused: ${turn.deniedTools.join(', ')})',
        rawOutput: '',
      );
    }

    // Throws SchemaRejection on parse or schema failure — LoopDriver owns the
    // single retry, so do NOT retry here.
    final Map<String, dynamic> decoded = schema.validate(
      _extractJson(turn.text),
    );

    final Object? rawAction = decoded['action'];
    if (rawAction is! Map<String, dynamic>) {
      throw SchemaRejection(
        validationError: 'action is not an object',
        rawOutput: turn.text,
      );
    }
    final Object? rawArgs = rawAction['args'];

    return ModelDecision(
      action: (
        tool: rawAction['tool']! as String,
        args: rawArgs is Map<String, dynamic>
            ? rawArgs
            : const <String, dynamic>{},
      ),
      thinking: turn.thinking.isEmpty ? null : turn.thinking,
      rationale: decoded['rationale'] as String?,
      waitStrategy: decoded['wait_strategy'] as String?,
      modelMetadata: <String, dynamic>{
        'acp_agent': _session.spec.label,
        'acp_stop_reason': turn.stopReason.name,
        'acp_denied_tools': turn.deniedTools,
      },
    );
  }

  /// First turn: system message, tool list, output contract, first
  /// observation.
  String _renderPriming(ConversationSnapshot snapshot, ActionSchema schema) {
    final StringBuffer b = StringBuffer()
      ..writeln(snapshot.systemMessage)
      ..writeln()
      ..writeln('## Available actions')
      ..writeln();
    for (final ToolDescriptor t in snapshot.tools) {
      b
        ..writeln('### ${t.name}')
        ..writeln(t.description)
        ..writeln('args schema: ${jsonEncode(t.inputSchema)}')
        ..writeln();
    }
    b
      ..writeln('## Output contract')
      ..writeln()
      ..writeln(
        'Reply with ONE JSON object and nothing else — no prose, no code '
        'fence, no commentary. It MUST validate against this JSON Schema:',
      )
      ..writeln()
      ..writeln(jsonEncode(schema.jsonSchema))
      ..writeln()
      ..writeln(
        'You have no tools and no file access. Do not attempt to read, '
        'write, or run anything — answer with the JSON object only.',
      )
      ..writeln()
      ..write(_renderNewestTurn(snapshot));
    return b.toString();
  }

  /// Later turns: only the newest turn. Validation-retry appends its error
  /// turn as the newest, so retries ride this path unchanged.
  String _renderNewestTurn(ConversationSnapshot snapshot) {
    if (snapshot.turns.isEmpty) return '(no observation)';
    final ConversationTurn turn = snapshot.turns.last;
    switch (turn) {
      case UserTurn():
        final StringBuffer b = StringBuffer()
          ..writeln('## Observation')
          ..writeln(_renderer.render(turn.observation));
        final Map<String, dynamic>? toolResult = turn.toolResult;
        if (toolResult != null) {
          b
            ..writeln()
            ..writeln('## Previous action result')
            ..writeln(jsonEncode(toolResult));
        }
        return b.toString();
      case AssistantTurn():
        // The agent's own last decision — it already has this in session
        // context; echoing it would duplicate history.
        return '(continue)';
    }
  }

  /// Tolerate a fenced or prose-wrapped object in phase 1.
  ///
  /// This is deliberate slack while we measure how often the agent complies
  /// with the output contract. If phase 1 shows it rarely emits bare JSON,
  /// that is the argument FOR phase 2's MCP tool-calling, not for making this
  /// helper cleverer.
  static String _extractJson(String raw) {
    final String text = raw.trim();
    final int start = text.indexOf('{');
    final int end = text.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return text;
    return text.substring(start, end + 1);
  }
}
