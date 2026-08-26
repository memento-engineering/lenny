/// Owns one spawned ACP agent process and the session on top of it.
///
/// This is the only file in the package that touches `dart:io`, which is why
/// leonard_acp exists at all: `leonard_agent` is declared web-compatible and
/// MUST NOT import `dart:io`, and `leonard_devtools` is a Flutter web build
/// that can neither spawn a process nor open a socket.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:acp_dart/acp_dart.dart';

import 'acp_agent_spec.dart';
import 'deny_all_client.dart';

/// ACP major protocol version this client speaks.
const int kAcpProtocolVersion = 1;

/// One agent turn's result.
class AcpTurn {
  const AcpTurn({
    required this.text,
    required this.stopReason,
    required this.thinking,
    required this.deniedTools,
  });

  /// Concatenated `agent_message_chunk` text for the turn.
  final String text;

  /// Why the agent stopped.
  final StopReason stopReason;

  /// Concatenated `agent_thought_chunk` text for the turn.
  final String thinking;

  /// Titles of tool calls refused by the deny-all permission handler.
  final List<String> deniedTools;
}

/// A live ACP agent: spawned process + initialized connection + session.
class AcpSession {
  AcpSession._(this._spec, this._process, this._connection);

  final AcpAgentSpec _spec;
  final Process _process;
  final ClientSideConnection _connection;

  InitializeResponse? _initialize;
  String? _sessionId;

  final StringBuffer _message = StringBuffer();
  final StringBuffer _thought = StringBuffer();
  final List<String> _denied = <String>[];

  final StreamController<String> _thoughtStream =
      StreamController<String>.broadcast();

  /// Live `agent_thought_chunk` text, for the DevTools thinking panel.
  Stream<String> get thoughts => _thoughtStream.stream;

  /// The agent's `initialize` response — protocol version and capabilities.
  /// Null until [start] completes.
  InitializeResponse? get initializeResponse => _initialize;

  /// Current ACP session id. Null until [newSession] completes.
  String? get sessionId => _sessionId;

  /// The spec this session was spawned from.
  AcpAgentSpec get spec => _spec;

  /// Spawn [spec] and complete the ACP `initialize` handshake.
  ///
  /// [onStderr] receives the agent's stderr lines — adapters are chatty on
  /// failure and this is usually where an auth problem shows up.
  static Future<AcpSession> start(
    AcpAgentSpec spec, {
    void Function(String line)? onStderr,
  }) async {
    final Process process = await Process.start(
      spec.command,
      spec.args,
      environment: spec.env.isEmpty ? null : spec.env,
      includeParentEnvironment: true,
    );

    late final AcpSession session;
    final DenyAllAcpClient client = DenyAllAcpClient(
      onAgentMessage: (String t) => session._message.write(t),
      onAgentThought: (String t) {
        session._thought.write(t);
        if (!session._thoughtStream.isClosed) session._thoughtStream.add(t);
      },
      onDenied: (String title) => session._denied.add(title),
    );

    final AcpStream stream = ndJsonStream(process.stdout, process.stdin);
    final ClientSideConnection connection = ClientSideConnection(
      (ClientSideConnection _) => client,
      stream,
    );

    session = AcpSession._(spec, process, connection);

    unawaited(
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((String line) => onStderr?.call(line)),
    );

    session._initialize = await connection.initialize(
      InitializeRequest(
        protocolVersion: kAcpProtocolVersion,
        // We advertise NO fs and NO terminal capability: combined with the
        // deny-all permission handler, the agent has nothing to act with.
        clientCapabilities: ClientCapabilities(),
      ),
    );

    return session;
  }

  /// Open an ACP session rooted at [cwd].
  ///
  /// [mcpServers] is empty in phase 1. It is the seam for phase 2's
  /// decision-capture MCP server — ACP's documented way for a client to put
  /// its own tools in front of the agent's model.
  Future<String> newSession({
    required String cwd,
    List<McpServerBase> mcpServers = const <McpServerBase>[],
  }) async {
    final NewSessionResponse response = await _connection.newSession(
      NewSessionRequest(cwd: cwd, mcpServers: mcpServers),
    );
    _sessionId = response.sessionId;
    return response.sessionId;
  }

  /// Send [text] as one prompt turn and collect the agent's reply.
  Future<AcpTurn> prompt(String text) async {
    final String? id = _sessionId;
    if (id == null) {
      throw StateError('AcpSession.prompt called before newSession');
    }

    _message.clear();
    _thought.clear();
    _denied.clear();

    final PromptResponse response = await _connection.prompt(
      PromptRequest(
        sessionId: id,
        prompt: <ContentBlock>[TextContentBlock(text: text)],
      ),
    );

    return AcpTurn(
      text: _message.toString(),
      stopReason: response.stopReason,
      thinking: _thought.toString(),
      deniedTools: List<String>.unmodifiable(_denied),
    );
  }

  /// Cancel the in-flight prompt turn.
  Future<void> cancel() async {
    final String? id = _sessionId;
    if (id == null) return;
    await _connection.cancel(CancelNotification(sessionId: id));
  }

  /// Kill the agent process and close the streams.
  Future<void> dispose() async {
    await _thoughtStream.close();
    _process.kill();
    await _process.exitCode;
  }
}
