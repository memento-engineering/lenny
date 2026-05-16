/// Shared in-process [VmService] fake bridging the agent's
/// `VmServiceClient.callServiceExtension` calls into a real
/// `ExplorationBinding`'s two test helpers (registry-routed:
/// methods whose `<ns>.<tool>` suffix is in
/// `pluginRegistry.mergedTools()` go to `invokePluginTool`;
/// everything else falls through to `invokeServiceExtension`).
///
/// Bound by `packages/exploration_agent/tool/agent_dogfood.dart` and
/// `packages/exploration_agent/test/e2e/dogfood_e2e_test.dart` —
/// both consumers of the dogfood harness (bead lenny-cx6.43).
///
/// Call sites today (4 total):
///   1. lenny-cvl.4 — `packages/exploration_flutter/test/binding_e2e_integration_test.dart` (origin)
///   2. lenny-cx6.41 — `packages/exploration_agent/test/integration/provider_loop_integration_test.dart` (clone 1)
///   3. lenny-cx6.43 — this file, imported by `tool/agent_dogfood.dart`
///   4. lenny-cx6.43 — this file, imported by `test/e2e/dogfood_e2e_test.dart`
///
/// TODO(lenny-imr): hoist all copies into
/// `packages/exploration_flutter/test_support/binding_vm_service_fake.dart`
/// once that sibling refactor lands. Until then, any wire-contract
/// change in `cvl.*` (extension prefixes, `args` encoding, RPC error
/// codes) MUST be mirrored across all four call sites.
///
/// Optional [observationFixture] (lenny-cx6.48): when non-null, calls
/// to `ext.flutter.exploration.core.get_stable_observation` short-
/// circuit to the fixture body wrapped in the binding's standard
/// `{type: 'Observation', value: <body>}` envelope, bypassing
/// `_binding.invokeServiceExtension` for that one method. Every other
/// extension and plugin tool routes normally regardless. This is the
/// seam the agent dogfood harness uses to serve canned observations
/// for prompt-tuning — without it the real binding's empty-tree
/// response is returned and the loaded fixture is ignored.
library;

import 'dart:convert';

import 'package:exploration_agent/src/dogfood/observation_fixture.dart';
import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:vm_service/vm_service.dart';

class BindingVmServiceFake extends VmService {
  BindingVmServiceFake(this._binding, {this.observationFixture})
      : super(const Stream<dynamic>.empty(), (_) {});

  final ExplorationBinding _binding;

  /// Optional canned observation. When non-null, calls to
  /// `ext.flutter.exploration.core.get_stable_observation` return
  /// `{type: 'Observation', value: observationFixture.body}` instead
  /// of executing the binding's real handler. Other extensions and
  /// plugin tools route normally regardless. (lenny-cx6.48)
  final ObservationFixture? observationFixture;

  /// Wire-name of the binding's stable-observation extension. The
  /// short-circuit branch keys off exactly this method; everything
  /// else falls through to the registry/extension routing below.
  static const String _kObservationMethod =
      'ext.flutter.exploration.core.get_stable_observation';

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) async {
    // Fixture-serving short-circuit (lenny-cx6.48). When a fixture is
    // configured, the binding's empty-tree observation is bypassed for
    // exactly this one method; everything else falls through to the
    // registry/extension routing below.
    final ObservationFixture? fx = observationFixture;
    if (fx != null && method == _kObservationMethod) {
      final Response r = Response();
      r.json = <String, dynamic>{
        'type': 'Observation',
        'value': fx.body,
      };
      return r;
    }
    final Map<String, String> stringArgs = <String, String>{
      for (final MapEntry<String, dynamic> e
          in (args ?? const <String, dynamic>{}).entries)
        e.key: e.value is String ? e.value as String : jsonEncode(e.value),
    };
    // Route by registry, not by URL prefix. Plugin tools (registered via
    // PluginContext.registerExtension) live in pluginRegistry.mergedTools()
    // keyed by '<ns>.<tool>'. Binding-owned extensions (handshake,
    // get_stable_observation, get_recent_errors, screenshot,
    // diagnostics_warnings) live in _extensionCallbacks and are reached
    // via invokeServiceExtension. The 'core.*' URL prefix is NOT a
    // routing signal — CorePlugin's per-tool extensions live in the
    // registry, not in _extensionCallbacks.
    const String prefix = 'ext.flutter.exploration.';
    if (!method.startsWith(prefix)) {
      throw RPCError(method, -32601, 'Unknown method "$method"');
    }
    final String suffix = method.substring(prefix.length);
    final String body;
    if (_binding.pluginRegistry.mergedTools().containsKey(suffix)) {
      body = await _binding.invokePluginTool(method, stringArgs);
    } else {
      body = await _binding.invokeServiceExtension(method, stringArgs);
    }
    final Response r = Response();
    r.json = jsonDecode(body) as Map<String, dynamic>;
    return r;
  }

  @override
  Future<void> dispose() async {}
}
