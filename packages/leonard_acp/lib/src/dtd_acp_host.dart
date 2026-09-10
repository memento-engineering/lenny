/// Host-side transport for exposing an ACP-backed [ModelProvider] over DTD.
///
/// DTD is only the wire: inference remains in the injected provider and retry
/// remains with the caller of the provider seam.
library;

import 'dart:async';

import 'package:dtd/dtd.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:leonard_agent/leonard_agent.dart';

const String _service = 'leonard.acp';
const String _method = 'decide';
const String _thinkingStream = 'leonard.acp.thinking';
const String _decisionType = 'ModelDecision';
const String _rejectionType = 'SchemaRejection';
const String _thinkingKind = 'ThinkingDelta';

const String _alreadyRegisteredMessage =
    'leonard.acp is already registered; stop the existing ACP host before '
    'starting another.';

/// Registers one DTD service method with optional handshake capabilities.
typedef DtdAcpRegisterService =
    Future<void> Function(
      String service,
      String method,
      DTDServiceCallback callback, {
      Map<String, Object?>? capabilities,
    });

/// Posts one event through a DTD stream.
typedef DtdAcpPostEvent =
    Future<void> Function(
      String streamId,
      String eventKind,
      Map<String, Object?> eventData,
    );

/// Exposes a host-side [ModelProvider] as `leonard.acp/decide` over DTD.
class DtdAcpHost {
  /// Creates a host from raw DTD operations.
  ///
  /// Tests can inject callbacks without opening a daemon connection.
  DtdAcpHost({
    required ModelProvider provider,
    required DtdAcpRegisterService registerService,
    required DtdAcpPostEvent postEvent,
  }) : _provider = provider,
       _registerService = registerService,
       _postEvent = postEvent;

  /// Creates a host backed by a live [DartToolingDaemon] connection.
  factory DtdAcpHost.fromDaemon(
    DartToolingDaemon dtd,
    ModelProvider provider,
  ) => DtdAcpHost(
    provider: provider,
    registerService: dtd.registerService,
    postEvent: dtd.postEvent,
  );

  final ModelProvider _provider;
  final DtdAcpRegisterService _registerService;
  final DtdAcpPostEvent _postEvent;

  StreamSubscription<void>? _thinkingSubscription;

  /// Registers the provider service and starts forwarding thinking deltas.
  ///
  /// Returns `false` when another DTD client already owns `leonard.acp` and
  /// reports an operator-facing message through [reportError]. Every other
  /// registration error is rethrown.
  Future<bool> start({void Function(String message)? reportError}) async {
    final ModelCapabilities capabilities = _provider.capabilities;
    try {
      await _registerService(
        _service,
        _method,
        _decide,
        capabilities: <String, Object?>{
          'vision': capabilities.vision,
          'preserve_thinking': capabilities.preserveThinking,
          'max_context': capabilities.maxContext,
          'supports_tool_use': capabilities.supportsToolUse,
        },
      );
    } on RpcException catch (error) {
      if (error.code != RpcErrorCodes.kServiceAlreadyRegistered) rethrow;
      reportError?.call(_alreadyRegisteredMessage);
      return false;
    }

    _thinkingSubscription = _provider
        .thinking()
        .asyncMap<void>(
          (ThinkingDelta delta) => _postEvent(
            _thinkingStream,
            _thinkingKind,
            <String, Object?>{...delta.toJson()},
          ),
        )
        .listen(
          null,
          onError: (Object error, StackTrace stackTrace) {
            reportError?.call(error.toString());
          },
        );
    return true;
  }

  Future<Map<String, Object?>> _decide(Parameters params) async {
    final ConversationSnapshot snapshot = ConversationSnapshot.fromJson(
      Map<String, dynamic>.from(params['snapshot'].asMap),
    );
    final ActionSchema schema = ActionSchema.fromJson(
      Map<String, dynamic>.from(params['schema'].asMap),
    );

    try {
      final ModelDecision decision = await _provider.decide(snapshot, schema);
      return <String, Object?>{
        'type': _decisionType,
        'decision': decision.toJson(),
      };
    } on SchemaRejection catch (rejection) {
      return <String, Object?>{
        'type': _rejectionType,
        'validation_error': rejection.validationError,
        'raw_output': rejection.rawOutput,
      };
    }
  }

  /// Stops forwarding provider thinking deltas.
  ///
  /// Calling this more than once is safe.
  Future<void> dispose() async {
    final StreamSubscription<void>? subscription = _thinkingSubscription;
    _thinkingSubscription = null;
    await subscription?.cancel();
  }
}
