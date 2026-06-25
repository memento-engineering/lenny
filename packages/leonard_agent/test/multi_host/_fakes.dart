/// Shared fakes for the multi-host unit tests (m3).
///
/// A [RecordingVmService] is a real [VmService] subclass whose
/// `callServiceExtension` is driven by a handler closure and which records
/// every executed action + dispose. Wrapping it in
/// [VmServiceClient.forTest] exercises the REAL per-host dispatch
/// (`ext.exploration.<ns>.<tool>`, JSON-encoded args) and the REAL
/// handshake decode — the multi-host layer is the only thing under test.
library;

import 'dart:async';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:vm_service/vm_service.dart';

/// One recorded service-extension call.
class RecordedCall {
  RecordedCall(this.method, this.isolateId, this.args);
  final String method;
  final String? isolateId;
  final Map<String, dynamic>? args;
}

/// A [VmService] fake that records calls and answers handshake +
/// get_stable_observation from canned values.
class RecordingVmService extends VmService {
  RecordingVmService({
    String contractVersion = '2',
    List<Map<String, dynamic>> extensions = const <Map<String, dynamic>>[],
    List<String> capabilities = const <String>[],
    Map<String, dynamic>? observation,
    Duration observeDelay = Duration.zero,
  }) : this._(
         // A never-closing input stream: the base VmService constructor wires
         // `onDone: () => dispose()`, so a `Stream.empty()` here would call
         // dispose() once at construction (skewing dispose counts). A
         // broadcast controller we never close keeps onDone from firing.
         StreamController<dynamic>.broadcast(),
         contractVersion: contractVersion,
         extensions: extensions,
         capabilities: capabilities,
         observation: observation ?? <String, dynamic>{},
         observeDelay: observeDelay,
       );

  RecordingVmService._(
    StreamController<dynamic> ctrl, {
    required this.contractVersion,
    required this.extensions,
    required this.capabilities,
    required this.observation,
    required this.observeDelay,
  }) : super(ctrl.stream, (_) {});

  final String contractVersion;
  final List<Map<String, dynamic>> extensions;
  final List<String> capabilities;

  /// The wire bundle returned (wrapped) by get_stable_observation.
  final Map<String, dynamic> observation;

  /// Artificial latency on get_stable_observation (to simulate a slow host).
  final Duration observeDelay;

  final List<RecordedCall> calls = <RecordedCall>[];
  int disposeCount = 0;

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) async {
    calls.add(RecordedCall(method, isolateId, args));
    final Response r = Response();
    if (method == 'ext.exploration.core.handshake') {
      r.json = <String, dynamic>{
        'contractVersion': contractVersion,
        'extensions': extensions,
        'capabilities': capabilities,
      };
    } else if (method == 'ext.exploration.core.get_stable_observation') {
      if (observeDelay > Duration.zero) {
        await Future<void>.delayed(observeDelay);
      }
      r.json = <String, dynamic>{'value': observation};
    } else {
      // A routed per-tool action: echo which method/args landed here.
      r.json = <String, dynamic>{'ok': true, 'method': method};
    }
    return r;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}

/// Build a [VmServiceClient] over a [RecordingVmService]. Set
/// [ownsConnection] to exercise the owning ([connect]) dispose path.
VmServiceClient clientOver(
  RecordingVmService vm, {
  bool ownsConnection = false,
}) => VmServiceClient.forTest(vm, 'iso', ownsConnection: ownsConnection);

/// Convenience: a manifest entry map for the handshake `extensions` list.
Map<String, dynamic> ext(String namespace, List<String> tools) =>
    <String, dynamic>{'namespace': namespace, 'tools': tools};
