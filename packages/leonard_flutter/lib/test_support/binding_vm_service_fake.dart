/// Shared in-process [VmService] fake bridging
/// `VmServiceClient.callServiceExtension` calls into a real
/// `LeonardBinding`'s two test helpers (registry-routed:
/// methods whose `<ns>.<tool>` suffix is in
/// `extensionRegistry.mergedTools()` go to `invokeExtensionTool`;
/// everything else falls through to `invokeServiceExtension`).
///
/// Hoisted from three sibling clones:
///   - `packages/leonard_flutter/test/binding_e2e_integration_test.dart` (origin)
///   - `packages/leonard_agent/test/integration/provider_loop_integration_test.dart`
///   - `packages/leonard_agent/test/_support/binding_vm_service_fake.dart`
///
/// Lives under `lib/test_support/` so it's importable as
/// `package:leonard_flutter/test_support/binding_vm_service_fake.dart`
/// but is NOT re-exported from `lib/leonard_flutter.dart` — opt-in
/// test-only surface.
///
/// Optional [observationFixture]: when non-null AND the
/// method equals `ext.exploration.core.get_stable_observation`,
/// the fake returns `{type: 'Observation', value: <fixture.body>}` and
/// bypasses the binding's real handler. Every other extension and
/// extension tool routes normally regardless.
///
/// The fixture parameter is `Object?` (NOT a typed
/// `ObservationFixture?`) because `leonard_flutter` cannot depend
/// on `leonard_agent` — the harness-side ObservationFixture lives
/// in `package:leonard_agent/src/dogfood/observation_fixture.dart`.
/// Callers pass whatever object exposes a `body` getter returning
/// `Map<String, dynamic>`; the fake reads it via `dynamic` dispatch.
library;

// The fake bridges into the binding's `@visibleForTesting`
// `invokeExtensionTool` and `invokeServiceExtension`. The file lives under
// `lib/test_support/` (opt-in test-only surface, not re-exported from
// the main library) so consumers can `package:`-import it from both
// tests and dev tooling (e.g. `tool/agent_dogfood_runner.dart`). That
// directory is NOT recognised as a test path by the analyzer, so the
// visible-for-testing warnings fire here unless suppressed — same
// trade-off the dogfood runner already documents.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';

import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:vm_service/vm_service.dart';

class BindingVmServiceFake extends VmService {
  BindingVmServiceFake(this._binding, {this.observationFixture})
    : super(const Stream<dynamic>.empty(), (_) {});

  final LeonardBinding _binding;

  /// Optional canned observation. When non-null, calls to
  /// `ext.exploration.core.get_stable_observation` return
  /// `{type: 'Observation', value: (observationFixture as dynamic).body}`
  /// instead of executing the binding's real handler. Other extensions
  /// and extension tools route normally regardless.
  ///
  /// Typed `Object?` to keep `leonard_flutter` independent of
  /// `leonard_agent`; the body is read via `dynamic` dispatch.
  final Object? observationFixture;

  /// Wire-name of the binding's stable-observation extension. The
  /// short-circuit branch keys off exactly this method; everything
  /// else falls through to the registry/extension routing below.
  static const String _kObservationMethod =
      'ext.exploration.core.get_stable_observation';

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) async {
    // Fixture-serving short-circuit. When a fixture is
    // configured, the binding's empty-tree observation is bypassed for
    // exactly this one method; everything else falls through to the
    // registry/extension routing below.
    final Object? fx = observationFixture;
    if (fx != null && method == _kObservationMethod) {
      final Map<String, dynamic> body =
          (fx as dynamic).body as Map<String, dynamic>;
      final Response r = Response();
      r.json = <String, dynamic>{'type': 'Observation', 'value': body};
      return r;
    }
    final Map<String, String> stringArgs = <String, String>{
      for (final MapEntry<String, dynamic> e
          in (args ?? const <String, dynamic>{}).entries)
        e.key: e.value is String ? e.value as String : jsonEncode(e.value),
    };
    // Route by registry, not by URL prefix. Extension tools (registered via
    // ExtensionContext.registerExtension) live in extensionRegistry.mergedTools()
    // keyed by '<ns>.<tool>'. Binding-owned extensions (handshake,
    // get_stable_observation, get_recent_errors, screenshot,
    // diagnostics_warnings) live in _extensionCallbacks and are reached
    // via invokeServiceExtension. The 'core.*' URL prefix is NOT a
    // routing signal — CoreExtension's per-tool extensions live in the
    // registry, not in _extensionCallbacks.
    const String prefix = 'ext.exploration.';
    if (!method.startsWith(prefix)) {
      throw RPCError(method, -32601, 'Unknown method "$method"');
    }
    final String suffix = method.substring(prefix.length);
    final String body;
    if (_binding.extensionRegistry.mergedTools().containsKey(suffix)) {
      body = await _binding.invokeExtensionTool(method, stringArgs);
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
