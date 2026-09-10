/// Web-safe DTD proxy for a host-side ACP model provider.
///
/// This file contains transport only. DTD is the wire, while the registered
/// host service owns the actual ACP provider and all inference.
library;

import 'package:dtd/dtd.dart';
import 'package:json_rpc_2/json_rpc_2.dart' show RpcException;
import 'package:leonard_agent/leonard_agent.dart';

const String _service = 'leonard.acp';
const String _method = 'decide';
const String _thinkingStream = 'leonard.acp.thinking';
const String _decisionType = 'ModelDecision';
const String _rejectionType = 'SchemaRejection';
const String _thinkingKind = 'ThinkingDelta';
const String _invalidHandshake = 'Invalid leonard.acp capability handshake';
const String _unavailableMessage =
    'Host-side ACP service leonard.acp/decide is unavailable; start '
    'leonard_acp:dtd_host and try again.';

/// Reads the shared stream of thinking-event data maps.
typedef DtdAcpRead = Stream<Map<String, Object?>> Function();

/// Calls the host-side decision service with one serialized request.
typedef DtdAcpCall =
    Future<Map<String, Object?>> Function(Map<String, Object?> request);

/// Indicates that the host-side ACP decision service is not available.
class DtdAcpUnavailable implements Exception {
  /// Creates an unavailable-service error with the operator-facing [message].
  const DtdAcpUnavailable([this.message = _unavailableMessage]);

  /// Instructions for restoring the host-side service.
  final String message;

  @override
  String toString() => message;
}

/// A web-safe [ModelProvider] proxy for `leonard.acp/decide` over DTD.
class DtdAcpModelProvider implements ModelProvider {
  /// Creates a proxy from raw callbacks and a capability handshake.
  ///
  /// [read] must return a re-listenable stream. [readiness] gates the first and
  /// every later decision on the single transport subscription established by
  /// the caller.
  DtdAcpModelProvider({
    required Map<String, Object?> capabilities,
    required DtdAcpRead read,
    required DtdAcpCall call,
    Future<void>? readiness,
  }) : _capabilities = _decodeCapabilities(capabilities),
       _read = read,
       _call = call,
       _readiness = readiness ?? Future<void>.value();

  /// Creates a proxy backed by one live [DartToolingDaemon] connection.
  ///
  /// [capabilities] is the `leonard.acp/decide` method capability map returned
  /// by `getRegisteredServices()`.
  factory DtdAcpModelProvider.fromDaemon(
    DartToolingDaemon dtd,
    Map<String, Object?> capabilities,
  ) {
    final Stream<Map<String, Object?>> thinkingEvents = dtd
        .onEvent(_thinkingStream)
        .where((DTDEvent event) => event.kind == _thinkingKind)
        .map((DTDEvent event) => event.data);
    final Future<void> streamListen = dtd.streamListen(_thinkingStream);

    return DtdAcpModelProvider(
      capabilities: capabilities,
      read: () => thinkingEvents,
      call: (Map<String, Object?> request) async =>
          (await dtd.call(_service, _method, params: request)).result,
      readiness: streamListen,
    );
  }

  final ModelCapabilities _capabilities;
  final DtdAcpRead _read;
  final DtdAcpCall _call;
  final Future<void> _readiness;

  @override
  ModelCapabilities get capabilities => _capabilities;

  @override
  Stream<ThinkingDelta> thinking() => _read().map(
    (Map<String, Object?> data) =>
        ThinkingDelta.fromJson(Map<String, dynamic>.from(data)),
  );

  @override
  Future<ModelDecision> decide(
    ConversationSnapshot snapshot,
    ActionSchema schema,
  ) async {
    try {
      await _readiness;
      final Map<String, Object?> response = await _call(<String, Object?>{
        'snapshot': snapshot.toJson(),
        'schema': schema.toJson(),
      });
      return switch (response['type']) {
        _decisionType => ModelDecision.fromJson(
          Map<String, dynamic>.from(response['decision'] as Map),
        ),
        _rejectionType => throw SchemaRejection(
          validationError: response['validation_error'] as String,
          rawOutput: response['raw_output'] as String,
        ),
        final Object? type => throw FormatException(
          'Unknown leonard.acp response type: $type',
        ),
      };
    } on RpcException catch (error) {
      if (error.code == RpcErrorCodes.kMethodNotFound ||
          error.code == RpcErrorCodes.kServiceDisappeared) {
        throw const DtdAcpUnavailable();
      }
      rethrow;
    }
  }

  static ModelCapabilities _decodeCapabilities(
    Map<String, Object?> capabilities,
  ) {
    final Object? vision = capabilities['vision'];
    final Object? preserveThinking = capabilities['preserve_thinking'];
    final Object? maxContext = capabilities['max_context'];
    final Object? supportsToolUse = capabilities['supports_tool_use'];
    if (vision is! bool ||
        preserveThinking is! bool ||
        maxContext is! int ||
        supportsToolUse is! bool) {
      throw const FormatException(_invalidHandshake);
    }
    return ModelCapabilities(
      vision: vision,
      preserveThinking: preserveThinking,
      maxContext: maxContext,
      supportsToolUse: supportsToolUse,
    );
  }
}
