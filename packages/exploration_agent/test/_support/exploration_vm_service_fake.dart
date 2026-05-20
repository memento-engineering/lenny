// packages/exploration_agent/test/_support/exploration_vm_service_fake.dart
/// Pure-Dart [VmService] fake for exploration_agent tests.
///
/// Replaces [BindingVmServiceFake] (from exploration_flutter/test_support/)
/// for tests that only need scripted RPC responses — no real Flutter binding,
/// no dart:ui, no flutter_test. (lenny-5o8)
///
/// Construction:
/// ```dart
/// final fake = ExplorationVmServiceFake(
///   handshakeResponse: <String, dynamic>{
///     'protocolVersion': '1',
///     'plugins': <dynamic>[],
///   },
///   observationBundle: <String, dynamic>{
///     'semantics': <dynamic>[],
///     'routes': <String>['login'],
///     'errors': <dynamic>[],
///     'stability': <String, dynamic>{
///       'policy': 'action_relative',
///       'reason': 'idle',
///     },
///     'plugins': <String, dynamic>{},
///   },
///   handlers: <String, Future<Map<String, dynamic>> Function(Map<String, dynamic>?)>{
///     'ext.flutter.exploration.router.navigate': (args) async =>
///         <String, dynamic>{'ok': true, 'value': args?['route_name']},
///   },
/// );
/// ```
library;

import 'dart:async';

import 'package:vm_service/vm_service.dart';

/// A single recorded [callServiceExtension] invocation.
class FakeRpcCall {
  FakeRpcCall({
    required this.method,
    this.isolateId,
    this.args,
  });

  final String method;
  final String? isolateId;
  final Map<String, dynamic>? args;

  @override
  String toString() =>
      'FakeRpcCall($method, isolateId=$isolateId, args=$args)';
}

/// Pure-Dart [VmService] subclass that returns scripted responses for
/// the `ext.flutter.exploration.*` RPC surface the agent loop exercises.
///
/// Three dispatch layers (evaluated in order):
/// 1. **Handshake** — any call to
///    `ext.flutter.exploration.core.handshake` returns [handshakeResponse]
///    verbatim as the [Response.json].
/// 2. **Observation** — any call to
///    `ext.flutter.exploration.core.get_stable_observation` returns
///    `{type: 'Observation', value: observationBundle}` when
///    [observationBundle] is non-null; throws [RPCError(-32601)] otherwise.
/// 3. **Handler table** — any other `ext.flutter.exploration.*` call is
///    looked up in [handlers] and invoked; throws [RPCError(-32601)] when
///    no entry is found.
///
/// Every call (matching or not) is appended to [calls] before the response
/// is produced, so tests can assert call count, ordering, and arguments.
class ExplorationVmServiceFake extends VmService {
  ExplorationVmServiceFake({
    required this.handshakeResponse,
    this.observationBundle,
    Map<String, Future<Map<String, dynamic>> Function(Map<String, dynamic>?)>?
        handlers,
  })  : handlers = handlers ??
            <String,
                Future<Map<String, dynamic>> Function(
                    Map<String, dynamic>?)>{},
        super(const Stream<dynamic>.empty(), (_) {});

  /// Scripted response for `ext.flutter.exploration.core.handshake`.
  /// Must include at least `protocolVersion` (String) and `plugins`
  /// (List) to satisfy [VmServiceClient.handshake]'s decode.
  final Map<String, dynamic> handshakeResponse;

  /// Scripted observation bundle returned under the binding's standard
  /// `{type: 'Observation', value: <bundle>}` envelope. When null,
  /// calls to `core.get_stable_observation` throw RPCError(-32601).
  final Map<String, dynamic>? observationBundle;

  /// Per-method dispatch table for calls not matched by the handshake or
  /// observation short-circuits. Keys are fully-qualified wire names
  /// (`ext.flutter.exploration.<ns>.<tool>`).
  final Map<String,
      Future<Map<String, dynamic>> Function(Map<String, dynamic>?)> handlers;

  /// Every [callServiceExtension] invocation, in order.
  final List<FakeRpcCall> calls = <FakeRpcCall>[];

  static const String _kHandshake =
      'ext.flutter.exploration.core.handshake';
  static const String _kObservation =
      'ext.flutter.exploration.core.get_stable_observation';

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) async {
    calls.add(FakeRpcCall(method: method, isolateId: isolateId, args: args));

    if (method == _kHandshake) {
      final Response r = Response();
      r.json = Map<String, dynamic>.from(handshakeResponse);
      return r;
    }

    if (method == _kObservation) {
      final Map<String, dynamic>? bundle = observationBundle;
      if (bundle == null) {
        throw RPCError(method, -32601, 'no observation bundle configured');
      }
      final Response r = Response();
      r.json = <String, dynamic>{
        'type': 'Observation',
        'value': bundle,
      };
      return r;
    }

    final handler = handlers[method];
    if (handler == null) {
      throw RPCError(method, -32601, 'Unknown method "$method"');
    }
    final Map<String, dynamic> json = await handler(args);
    final Response r = Response();
    r.json = json;
    return r;
  }

  @override
  Future<void> dispose() async {}
}
