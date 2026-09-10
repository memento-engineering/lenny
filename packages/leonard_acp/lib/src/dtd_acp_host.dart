/// Host-side transport for exposing an ACP-backed [ModelProvider] over DTD.
///
/// DTD is only the wire: inference remains in the injected provider and retry
/// remains with the caller of the provider seam.
library;

import 'dart:async';

import 'package:dtd/dtd.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:leonard_agent/leonard_agent.dart';

import 'acp_agent_spec.dart';
import 'acp_model_provider.dart' show kAcpDefaultCapabilities;

const String _service = 'leonard.acp';
const String _decideMethod = 'decide';
const String _newSessionMethod = 'session/new';
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

/// Opens one host-owned ACP session for [spec].
typedef DtdAcpOpenSession =
    Future<DtdAcpSessionBinding> Function(AcpAgentSpec spec);

/// One opened ACP provider plus the model state returned by `session/new`.
class DtdAcpSessionBinding {
  /// Creates a host-owned session binding.
  DtdAcpSessionBinding({
    required this.provider,
    required List<String> availableModels,
    required this.currentModelId,
    required Future<void> Function() dispose,
  }) : availableModels = List<String>.unmodifiable(availableModels),
       _dispose = dispose;

  /// Provider that delegates decisions to this ACP session.
  final ModelProvider provider;

  /// Exact model ids advertised by the ACP agent.
  final List<String> availableModels;

  /// Exact current model id after the requested pin was applied.
  final String? currentModelId;

  final Future<void> Function() _dispose;
  Future<void>? _disposal;

  /// Releases the underlying session once; repeated calls share the result.
  Future<void> dispose() => _disposal ??= Future<void>.sync(_dispose);
}

/// Exposes value-selected host-side ACP sessions over one DTD service.
class DtdAcpHost {
  /// Creates a host from raw DTD operations.
  ///
  /// Tests can inject callbacks without opening a daemon connection.
  DtdAcpHost({
    required Map<String, AcpAgentSpec> acpAgentSpecs,
    required DtdAcpOpenSession openSession,
    required DtdAcpRegisterService registerService,
    required DtdAcpPostEvent postEvent,
    ModelCapabilities capabilities = kAcpDefaultCapabilities,
  }) : _agentSpecs = Map<String, AcpAgentSpec>.unmodifiable(acpAgentSpecs),
       _specsByLabel = Map<String, AcpAgentSpec>.unmodifiable(
         <String, AcpAgentSpec>{
           for (final AcpAgentSpec spec in acpAgentSpecs.values)
             spec.label: spec,
         },
       ),
       _openSession = openSession,
       _registerService = registerService,
       _postEvent = postEvent,
       _capabilities = capabilities;

  /// Creates a host backed by a live [DartToolingDaemon] connection.
  factory DtdAcpHost.fromDaemon(
    DartToolingDaemon dtd, {
    required Map<String, AcpAgentSpec> acpAgentSpecs,
    required DtdAcpOpenSession openSession,
    ModelCapabilities capabilities = kAcpDefaultCapabilities,
  }) => DtdAcpHost(
    acpAgentSpecs: acpAgentSpecs,
    openSession: openSession,
    registerService: dtd.registerService,
    postEvent: dtd.postEvent,
    capabilities: capabilities,
  );

  final Map<String, AcpAgentSpec> _agentSpecs;
  final Map<String, AcpAgentSpec> _specsByLabel;
  final DtdAcpOpenSession _openSession;
  final DtdAcpRegisterService _registerService;
  final DtdAcpPostEvent _postEvent;
  final ModelCapabilities _capabilities;

  DtdAcpSessionBinding? _binding;
  StreamSubscription<void>? _thinkingSubscription;
  void Function(String message)? _reportError;

  /// Registers decision and session-opening methods on `leonard.acp`.
  ///
  /// Returns `false` when another DTD client already owns `leonard.acp` and
  /// reports an operator-facing message through [reportError]. Every other
  /// registration error is rethrown.
  Future<bool> start({void Function(String message)? reportError}) async {
    _reportError = reportError;
    try {
      await _registerService(
        _service,
        _decideMethod,
        _decide,
        capabilities: <String, Object?>{
          'vision': _capabilities.vision,
          'preserve_thinking': _capabilities.preserveThinking,
          'max_context': _capabilities.maxContext,
          'supports_tool_use': _capabilities.supportsToolUse,
        },
      );
      await _registerService(
        _service,
        _newSessionMethod,
        _newSession,
        capabilities: <String, Object?>{
          'harness_labels': <String>[
            for (final AcpAgentSpec spec in _agentSpecs.values) spec.label,
          ],
        },
      );
    } on RpcException catch (error) {
      if (error.code != RpcErrorCodes.kServiceAlreadyRegistered) rethrow;
      reportError?.call(_alreadyRegisteredMessage);
      return false;
    }
    return true;
  }

  Future<Map<String, Object?>> _newSession(Parameters params) async {
    final String harnessLabel = params['harness_label'].asString;
    final String modelId = params['model_id'].asString;
    final AcpAgentSpec? selected = _specsByLabel[harnessLabel];
    if (selected == null) {
      throw ArgumentError('Unknown ACP harness label: $harnessLabel');
    }

    final DtdAcpSessionBinding replacement = await _openSession(
      selected.withModelOverride(modelId),
    );
    final DtdAcpSessionBinding? previous = _binding;
    final StreamSubscription<void>? previousThinking = _thinkingSubscription;

    _binding = replacement;
    _thinkingSubscription = _forwardThinking(replacement.provider);
    await previousThinking?.cancel();
    await previous?.dispose();

    return <String, Object?>{
      'available_models': replacement.availableModels,
      'current_model_id': replacement.currentModelId,
    };
  }

  StreamSubscription<void> _forwardThinking(ModelProvider provider) => provider
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
          _reportError?.call(error.toString());
        },
      );

  Future<Map<String, Object?>> _decide(Parameters params) async {
    final ModelProvider? provider = _binding?.provider;
    if (provider == null) {
      throw StateError('ACP session has not been opened');
    }
    final ConversationSnapshot snapshot = ConversationSnapshot.fromJson(
      Map<String, dynamic>.from(params['snapshot'].asMap),
    );
    final ActionSchema schema = ActionSchema.fromJson(
      Map<String, dynamic>.from(params['schema'].asMap),
    );

    try {
      final ModelDecision decision = await provider.decide(snapshot, schema);
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

  /// Stops forwarding thinking and disposes the current ACP session.
  ///
  /// Calling this more than once is safe.
  Future<void> dispose() async {
    final StreamSubscription<void>? subscription = _thinkingSubscription;
    final DtdAcpSessionBinding? binding = _binding;
    _thinkingSubscription = null;
    _binding = null;
    await subscription?.cancel();
    await binding?.dispose();
  }
}
