/// The client half of the ACP connection: a deny-all permission handler
/// plus update fan-out.
///
/// Tool suppression is done HERE, on the client side, not with per-agent CLI
/// flags (`copilot --available-tools=""` and friends). Every ACP agent must
/// ask before it acts, so refusing every `session/request_permission` neuters
/// tool execution on ANY agent — which is the whole reason for riding ACP.
///
/// We advertise no `fs` and no `terminal` capability, so the file and
/// terminal methods return null: the agent is told up front they do not
/// exist.
library;

import 'package:acp_dart/acp_dart.dart';

/// Callback for streamed agent text (the decision) and thoughts.
typedef AcpChunkSink = void Function(String text);

/// A [Client] that refuses every permission request and forwards the
/// message/thought streams to Leonard.
class DenyAllAcpClient implements Client {
  DenyAllAcpClient({
    required this.onAgentMessage,
    required this.onAgentThought,
    this.onDenied,
  });

  /// Receives `agent_message_chunk` text — the decision payload.
  final AcpChunkSink onAgentMessage;

  /// Receives `agent_thought_chunk` text — routed to the thinking panel.
  final AcpChunkSink onAgentThought;

  /// Notified with the tool title each time a permission request is refused.
  /// A high count here means the agent is trying to work instead of
  /// answering, which is the signal the prompt needs tightening.
  final void Function(String toolTitle)? onDenied;

  @override
  Future<RequestPermissionResponse> requestPermission(
    RequestPermissionRequest params,
  ) async {
    onDenied?.call(params.toolCall.title ?? params.toolCall.toolCallId);

    // Prefer an explicit reject option so the agent learns the refusal is
    // durable; fall back to cancelling the turn when the agent offered no
    // reject option at all.
    final PermissionOption? reject =
        _firstOfKind(params.options, PermissionOptionKind.rejectAlways) ??
        _firstOfKind(params.options, PermissionOptionKind.rejectOnce);

    if (reject == null) {
      return RequestPermissionResponse(outcome: CancelledOutcome());
    }
    return RequestPermissionResponse(
      outcome: SelectedOutcome(optionId: reject.optionId),
    );
  }

  static PermissionOption? _firstOfKind(
    List<PermissionOption> options,
    PermissionOptionKind kind,
  ) {
    for (final PermissionOption o in options) {
      if (o.kind == kind) return o;
    }
    return null;
  }

  @override
  Future<void> sessionUpdate(SessionNotification params) async {
    final SessionUpdate update = params.update;
    if (update is AgentMessageChunkSessionUpdate) {
      final ContentBlock content = update.content;
      if (content is TextContentBlock) onAgentMessage(content.text);
    } else if (update is AgentThoughtChunkSessionUpdate) {
      final ContentBlock content = update.content;
      if (content is TextContentBlock) onAgentThought(content.text);
    }
    // tool_call / plan / mode updates are deliberately ignored in phase 1 —
    // nothing executes, so there is no tool result to thread back.
  }

  // ---- capabilities we do NOT advertise -------------------------------
  // Returning null is the contract for an unsupported client method.

  @override
  Future<WriteTextFileResponse>? writeTextFile(WriteTextFileRequest params) =>
      null;

  @override
  Future<ReadTextFileResponse>? readTextFile(ReadTextFileRequest params) =>
      null;

  @override
  Future<CreateTerminalResponse>? createTerminal(
    CreateTerminalRequest params,
  ) => null;

  @override
  Future<TerminalOutputResponse>? terminalOutput(
    TerminalOutputRequest params,
  ) => null;

  @override
  Future<ReleaseTerminalResponse?>? releaseTerminal(
    ReleaseTerminalRequest params,
  ) => null;

  @override
  Future<WaitForTerminalExitResponse>? waitForTerminalExit(
    WaitForTerminalExitRequest params,
  ) => null;

  @override
  Future<KillTerminalCommandResponse?>? killTerminal(
    KillTerminalCommandRequest params,
  ) => null;

  @override
  Future<Map<String, dynamic>>? extMethod(
    String method,
    Map<String, dynamic> params,
  ) => null;

  @override
  Future<void>? extNotification(String method, Map<String, dynamic> params) =>
      null;
}
