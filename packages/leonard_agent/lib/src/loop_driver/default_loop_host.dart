/// Production [LoopHost] implementation that wires the loop driver to
/// an [LeonardSession] (and its underlying `VmServiceClient`) plus
/// caller-supplied tool descriptors.
///
/// The handshake's `ExtensionManifestEntry` list only carries
/// pre-namespaced tool *names*; full [ToolDescriptor]s (including
/// `inputSchema`) are supplied by the caller (cx6.20 CLI / cx6.21
/// DevTools) keyed by plugin namespace. This host intersects that
/// descriptor map with the active handshake namespaces, then subtracts
/// auto-disabled namespaces to produce the per-turn merged tool list.
///
/// Transport-level failures (`RPCError`s reported as
/// connection-disposed/closed, or a bare `StateError` from a disposed
/// `VmService`) are translated into [VmServiceConnectionLost] so the
/// driver can terminate the session with `harnessError =
/// connection_lost`. Method-level `RPCError`s — i.e. extension-reported
/// failures with non-transport codes — propagate unwrapped.
///
/// Plugin notification (`onActionExecutedAll`) runs *inside* the target
/// app's `LeonardBinding` during the same `executeAction`
/// round-trip, so the harness-side [notifyExtensions] is intentionally a
/// no-op — dispatching again here would double-fire plugin handlers.
library;

import 'package:vm_service/vm_service.dart' show RPCError;

import '../observation/models.dart';
import '../provider/types.dart';
import '../session.dart';
import '../session/observation_puller.dart';
import 'loop_host.dart';
import 'types.dart';

/// VM-service [RPCError.code] values that indicate the underlying
/// transport (websocket / DDS) is gone rather than the extension
/// reporting a method-level failure. -32000 ("server error") and
/// -32603 ("internal error") are the codes `package:vm_service` emits
/// when its socket layer is torn down mid-call.
const Set<int> _kTransportRpcCodes = <int>{-32000, -32603};

/// The core namespace must never be disabled — its tools are essential
/// for every agent action. Disabling it collapses the action-schema oneOf.
const String _kCoreNamespace = 'core';

class DefaultLoopHost implements LoopHost {
  /// Build a host on top of an already-`start()`ed [LeonardSession].
  ///
  /// * [coreTools] — base tool list always included in `mergedTools()`.
  /// * [extensionTools] — plugin tool descriptors keyed by namespace.
  ///   Entries whose key is absent from the handshake manifest are
  ///   ignored; entries whose namespace is later auto-disabled are
  ///   excluded from `mergedTools()`/`activeExtensionNamespaces()`.
  /// * [goal], [agentsMd] — pre-loaded session text (no disk reads
  ///   inside the host).
  /// * [policy] — stability policy applied to every `observe()` call.
  DefaultLoopHost.fromSession({
    required LeonardSession session,
    required List<ToolDescriptor> coreTools,
    required Map<String, List<ToolDescriptor>> extensionTools,
    required String goal,
    required String agentsMd,
    StabilityPolicy policy = StabilityPolicy.actionRelative,
  }) : _session = session,
       _coreTools = List<ToolDescriptor>.unmodifiable(coreTools),
       _pluginTools = <String, List<ToolDescriptor>>{
         for (final MapEntry<String, List<ToolDescriptor>> e
             in extensionTools.entries)
           e.key: List<ToolDescriptor>.unmodifiable(e.value),
       },
       _goal = goal,
       _agentsMd = agentsMd,
       _policy = policy;

  final LeonardSession _session;
  final List<ToolDescriptor> _coreTools;
  final Map<String, List<ToolDescriptor>> _pluginTools;
  final String _goal;
  final String _agentsMd;
  final StabilityPolicy _policy;
  final Set<String> _disabled = <String>{};

  @override
  String get goal => _goal;

  @override
  String get agentsMd => _agentsMd;

  @override
  Set<String> activeExtensionNamespaces() {
    return <String>{
      for (final p in _session.handshake.plugins)
        if (_pluginTools.containsKey(p.namespace) &&
            !_disabled.contains(p.namespace))
          p.namespace,
    };
  }

  @override
  List<ToolDescriptor> mergedTools() {
    final List<ToolDescriptor> out = <ToolDescriptor>[..._coreTools];
    for (final String ns in activeExtensionNamespaces()) {
      out.addAll(_pluginTools[ns]!);
    }
    return List<ToolDescriptor>.unmodifiable(out);
  }

  @override
  void disableExtension(String namespace, String reason) {
    // Defense-in-depth: core is essential and must never be removed.
    // The primary guard lives in LoopDriver._accountExtensionStrikes, but
    // we reject any call here too to prevent future callers from
    // accidentally stripping core tools (lenny-4jn).
    if (namespace == _kCoreNamespace) return;
    if (_disabled.add(namespace)) {
      _session.disableExtension(namespace, reason);
    }
    // Repeated disables are no-ops: ExtensionAutoDisabled fires exactly
    // once per namespace because the host short-circuits.
  }

  @override
  Future<Observation> observe() => _callTransport<Observation>(
    () => _session.pullObservation(policy: _policy),
  );

  @override
  Future<Map<String, dynamic>> executeAction(
    String tool,
    Map<String, dynamic> args,
  ) => _callTransport<Map<String, dynamic>>(
    () => _session.client.executeAction(tool, args),
  );

  @override
  Future<void> notifyExtensions(
    String tool,
    Map<String, dynamic> args,
    Map<String, dynamic> result,
  ) async {
    // Intentionally empty. Plugin-side notification
    // (`ExtensionRegistry.onActionExecutedAll`) runs in-process inside the
    // binding during `executeAction`. Dispatching again here would
    // double-fire plugin handlers.
  }

  /// Wrap a session/client call so that transport failures surface as
  /// [VmServiceConnectionLost] (which the driver translates into a
  /// `connection_lost` termination). Method-level `RPCError`s — i.e.
  /// extension-reported failures with codes outside [_kTransportRpcCodes]
  /// and non-transport messages — propagate unwrapped.
  Future<T> _callTransport<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on RPCError catch (e) {
      final String m = e.message.toLowerCase();
      if (_kTransportRpcCodes.contains(e.code) ||
          m.contains('disposed') ||
          m.contains('connection closed')) {
        throw VmServiceConnectionLost(e);
      }
      rethrow;
    } on StateError catch (e) {
      // `package:vm_service` throws StateError after dispose() — treat
      // as a transport-gone signal.
      throw VmServiceConnectionLost(e);
    }
  }
}
