/// ACP (Agent Client Protocol) model provider for Leonard.
///
/// Drives any ACP-compatible coding agent — Claude via the ACP adapter,
/// GitHub Copilot CLI, and anything else that speaks the protocol — behind
/// `leonard_agent`'s `ModelProvider` seam. The agent is a value
/// ([AcpAgentSpec]), never a code path.
///
/// Uses `dart:io` (process spawn), so this package is NOT web-compatible and
/// cannot be depended on by `leonard_agent` or `leonard_devtools`.
library;

export 'src/acp_agent_spec.dart' show AcpAgentSpec;
export 'src/acp_model_provider.dart'
    show AcpModelProvider, kAcpDefaultCapabilities;
export 'src/acp_session.dart' show AcpSession, AcpTurn, kAcpProtocolVersion;
export 'src/deny_all_client.dart' show AcpChunkSink, DenyAllAcpClient;
