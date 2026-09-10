/// Web-safe DTD proxy for a host-side ACP model provider.
///
/// This file contains transport only. DTD is the wire, while the registered
/// host service owns the actual ACP provider and all inference.
library;

import 'package:dtd/dtd.dart';
import 'package:dart_service_protocol_shared/dart_service_protocol_shared.dart'
    show ClientServiceInfo;
import 'package:json_rpc_2/json_rpc_2.dart' show RpcException;
import 'package:leonard_agent/leonard_agent.dart';

const String _service = 'leonard.acp';
const String _method = 'decide';
const String _newSessionMethod = 'session/new';
const String _thinkingStream = 'leonard.acp.thinking';
const String _decisionType = 'ModelDecision';
const String _rejectionType = 'SchemaRejection';
const String _thinkingKind = 'ThinkingDelta';
const String _invalidHandshake = 'Invalid leonard.acp capability handshake';
const String _invalidSessionHandshake =
    'Invalid leonard.acp session/new capability handshake';
const String _invalidSessionModels =
    'Invalid leonard.acp session/new model response';
const String _unavailableMessage =
    'Host-side ACP service leonard.acp/decide is unavailable; start '
    'leonard_acp:dtd_host and try again.';

/// Reads the shared stream of thinking-event data maps.
typedef DtdAcpRead = Stream<Map<String, Object?>> Function();

/// Calls the host-side decision service with one serialized request.
typedef DtdAcpCall =
    Future<Map<String, Object?>> Function(Map<String, Object?> request);

/// Lists the client services currently registered with DTD.
typedef DtdAcpListServices = Future<List<ClientServiceInfo>> Function();

/// Opens one selected host-side ACP session.
typedef DtdAcpNewSession =
    Future<Map<String, Object?>> Function(String harnessLabel, String modelId);

/// Builds the decision proxy after session readiness has been established.
typedef DtdAcpProviderBuilder =
    DtdAcpModelProvider Function(
      Map<String, Object?> capabilities,
      Future<void> readiness,
    );

/// Discovery data advertised by the registered ACP host.
class DtdAcpHostInfo {
  /// Creates validated host discovery data.
  DtdAcpHostInfo({
    required List<String> harnessLabels,
    required Map<String, Object?> capabilities,
  }) : harnessLabels = List<String>.unmodifiable(harnessLabels),
       capabilities = Map<String, Object?>.unmodifiable(capabilities);

  /// Harness labels accepted by `leonard.acp/session/new`.
  final List<String> harnessLabels;

  /// Capability handshake for `leonard.acp/decide`.
  final Map<String, Object?> capabilities;
}

/// Model state returned by a host-side ACP `session/new` call.
class DtdAcpSessionModels {
  /// Creates decoded ACP model state.
  DtdAcpSessionModels({
    required List<String> availableModels,
    required this.currentModelId,
  }) : availableModels = List<String>.unmodifiable(availableModels);

  /// Exact model ids advertised by the selected agent.
  final List<String> availableModels;

  /// Exact current model id after host-side pin resolution.
  final String? currentModelId;
}

/// Discovers and opens host-side ACP sessions without browser HTTP.
class DtdAcpPanelClient {
  /// Creates a client from callback seams suitable for unit tests.
  DtdAcpPanelClient({
    required DtdAcpListServices listServices,
    required DtdAcpNewSession newSession,
    required DtdAcpProviderBuilder providerBuilder,
  }) : _listServices = listServices,
       _newSession = newSession,
       _providerBuilder = providerBuilder;

  /// Creates a client that borrows the current DTD connection per operation.
  factory DtdAcpPanelClient.fromConnection(
    DartToolingDaemon? Function() connection,
  ) => DtdAcpPanelClient(
    listServices: () async {
      final DartToolingDaemon? dtd = connection();
      if (dtd == null) return const <ClientServiceInfo>[];
      return (await dtd.getRegisteredServices()).clientServices;
    },
    newSession: (String harnessLabel, String modelId) async {
      final DartToolingDaemon? dtd = connection();
      if (dtd == null) throw const DtdAcpUnavailable();
      return (await dtd.call(
        _service,
        _newSessionMethod,
        params: <String, Object?>{
          'harness_label': harnessLabel,
          'model_id': modelId,
        },
      )).result;
    },
    providerBuilder:
        (Map<String, Object?> capabilities, Future<void> readiness) {
          final DartToolingDaemon? dtd = connection();
          if (dtd == null) throw const DtdAcpUnavailable();
          return DtdAcpModelProvider.fromDaemon(
            dtd,
            capabilities,
            sessionReadiness: readiness,
          );
        },
  );

  /// Creates a client that consistently reports no registered ACP host.
  factory DtdAcpPanelClient.unavailable() => DtdAcpPanelClient(
    listServices: () async => const <ClientServiceInfo>[],
    newSession: (String harnessLabel, String modelId) async =>
        throw const DtdAcpUnavailable(),
    providerBuilder:
        (Map<String, Object?> capabilities, Future<void> readiness) =>
            throw const DtdAcpUnavailable(),
  );

  final DtdAcpListServices _listServices;
  final DtdAcpNewSession _newSession;
  final DtdAcpProviderBuilder _providerBuilder;
  DtdAcpHostInfo? _host;

  /// Refreshes ACP registration, returning null only when no host exists.
  Future<DtdAcpHostInfo?> refreshHost() async {
    _host = null;
    ClientServiceInfo? service;
    for (final ClientServiceInfo candidate in await _listServices()) {
      if (candidate.name == _service) {
        service = candidate;
        break;
      }
    }
    if (service == null) return null;

    final Map<String, Object?>? capabilities =
        service.methods[_method]?.capabilities;
    if (capabilities == null) {
      throw const FormatException(_invalidHandshake);
    }
    DtdAcpModelProvider.decodeCapabilities(capabilities);

    final Map<String, Object?>? sessionCapabilities =
        service.methods[_newSessionMethod]?.capabilities;
    final Object? rawLabels = sessionCapabilities?['harness_labels'];
    if (rawLabels is! List ||
        rawLabels.any((Object? label) => label is! String)) {
      throw const FormatException(_invalidSessionHandshake);
    }
    final DtdAcpHostInfo info = DtdAcpHostInfo(
      harnessLabels: rawLabels.cast<String>(),
      capabilities: capabilities,
    );
    _host = info;
    return info;
  }

  /// Opens a selected ACP session and strictly decodes its model state.
  Future<DtdAcpSessionModels> newSession({
    required String harnessLabel,
    required String modelId,
  }) async {
    final Map<String, Object?> response = await _newSession(
      harnessLabel,
      modelId,
    );
    final Object? rawModels = response['available_models'];
    final Object? current = response['current_model_id'];
    if (rawModels is! List ||
        rawModels.any((Object? model) => model is! String) ||
        (current != null && current is! String)) {
      throw const FormatException(_invalidSessionModels);
    }
    return DtdAcpSessionModels(
      availableModels: rawModels.cast<String>(),
      currentModelId: current as String?,
    );
  }

  /// Builds a provider whose first decision awaits the selected session.
  DtdAcpModelProvider buildProvider({
    required String harnessLabel,
    required String modelId,
  }) {
    final DtdAcpHostInfo? host = _host;
    if (host == null) {
      throw StateError('ACP host has not been discovered');
    }
    final Future<void> readiness = newSession(
      harnessLabel: harnessLabel,
      modelId: modelId,
    );
    return _providerBuilder(host.capabilities, readiness);
  }
}

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
  }) : _capabilities = decodeCapabilities(capabilities),
       _read = read,
       _call = call,
       _readiness = readiness ?? Future<void>.value();

  /// Creates a proxy backed by one live [DartToolingDaemon] connection.
  ///
  /// [capabilities] is the `leonard.acp/decide` method capability map returned
  /// by `getRegisteredServices()`. [sessionReadiness] is awaited alongside
  /// the one thinking-stream subscription before the first decision.
  factory DtdAcpModelProvider.fromDaemon(
    DartToolingDaemon dtd,
    Map<String, Object?> capabilities, {
    Future<void>? sessionReadiness,
  }) {
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
      readiness: Future.wait<void>(<Future<void>>[
        streamListen,
        if (sessionReadiness != null) sessionReadiness,
      ]),
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

  /// Strictly decodes the host capability handshake.
  static ModelCapabilities decodeCapabilities(
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
