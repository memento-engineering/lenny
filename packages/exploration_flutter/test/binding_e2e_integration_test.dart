/// End-to-end integration test for the agent ↔ binding wire contract
/// (parent epic lenny-cvl).
///
/// Boots a real [ExplorationBinding] with the host-installed [CorePlugin]
/// plus a test-local `_SampleEchoPlugin` and drives
/// handshake → observation → tool call through the agent's
/// [VmServiceClient] / [ExplorationSession]. The siblings lenny-cvl.1–3
/// reconciled the three surfaces independently; this test exercises all
/// three at once against the same binding so future drift between the
/// agent and the binding cannot ship undetected.
library;

import 'dart:async';
import 'dart:convert';

import 'package:exploration_agent/exploration_agent.dart';
import 'package:exploration_flutter/contract.dart';
import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart';

/// Tool contributed by [_SampleEchoPlugin]: returns the `text` argument
/// verbatim wrapped in a successful [ToolResult].
class _EchoTool extends ExplorationTool {
  const _EchoTool();
  @override
  String get name => 'echo';
  @override
  String get description => 'echo back the text arg';
  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'text': <String, Object?>{'type': 'string'},
        },
        'required': <String>['text'],
      });
  @override
  Future<ToolResult> call(Map<String, Object?> args) async =>
      ToolResult(ok: true, value: args['text']);
}

/// User plugin under namespace `sample` contributing one tool, `echo`.
///
/// Deliberately does NOT call `ctx.registerExtension` from
/// [initialize] — the test reaches the tool through the binding's
/// `invokePluginTool` → `mergedTools()['sample.echo']` seam, which is
/// the deliberate test-only path documented on
/// [ExplorationBinding.invokePluginTool]. Plugin tools register their
/// VM service extensions via `dart:developer.registerExtension`
/// directly from inside [CorePlugin.initialize] (see
/// `core_plugin_registration_test.dart`); this test exists precisely
/// to cover the in-process wire-contract dispatch without a live VM.
class _SampleEchoPlugin extends ExplorationPlugin {
  @override
  String get namespace => 'sample';
  @override
  List<ExplorationTool> get tools => const <ExplorationTool>[_EchoTool()];
  @override
  Future<void> initialize(PluginContext ctx) async {}
  @override
  Future<Map<String, Object?>?> observe(ObservationContext ctx) async => null;
  @override
  Future<BusyState> busyState() async => BusyState.idle;
  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}
  @override
  Future<void> dispose() async {}
}

/// In-process fake [VmService] that bridges
/// `VmServiceClient.callServiceExtension` straight into the real
/// binding's two test helpers — [ExplorationBinding.invokeServiceExtension]
/// for the host-owned `core.*` extensions and
/// [ExplorationBinding.invokePluginTool] for plugin-registered tools.
///
/// The bridge mirrors what the live VM service does on the wire: it
/// converts the agent's `Map<String, dynamic>? args` to the
/// `Map<String, String>` shape `dart:developer` hands extensions, by
/// JSON-encoding every non-string value (the binding's
/// `decodeServiceExtensionParams` reverses the encoding on the way in).
class _BindingVmServiceFake extends VmService {
  _BindingVmServiceFake(this._binding)
      : super(const Stream<dynamic>.empty(), (_) {});

  final ExplorationBinding _binding;

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) async {
    final Map<String, String> stringArgs = <String, String>{
      for (final MapEntry<String, dynamic> e
          in (args ?? const <String, dynamic>{}).entries)
        e.key: e.value is String ? e.value as String : jsonEncode(e.value),
    };
    const String corePrefix = 'ext.flutter.exploration.core.';
    const String pluginPrefix = 'ext.flutter.exploration.';
    final String body;
    if (method.startsWith(corePrefix)) {
      body = await _binding.invokeServiceExtension(method, stringArgs);
    } else if (method.startsWith(pluginPrefix)) {
      body = await _binding.invokePluginTool(method, stringArgs);
    } else {
      throw RPCError(method, -32601, 'Unknown method "$method"');
    }
    final Response r = Response();
    r.json = jsonDecode(body) as Map<String, dynamic>;
    return r;
  }

  @override
  Future<void> dispose() async {}
}

/// Stand-in VmService whose `callServiceExtension` unconditionally
/// raises the JSON-RPC "method not found" error — what a live VM would
/// emit if the target isolate has no `ExplorationBinding` installed.
/// Used by the regression guard for the original "Binding not detected"
/// symptom (the parent epic lenny-cvl).
class _RejectingVmService extends VmService {
  _RejectingVmService() : super(const Stream<dynamic>.empty(), (_) {});

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) async {
    throw RPCError(method, -32601, 'Unknown method "$method"');
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  late ExplorationBinding binding;
  late _BindingVmServiceFake fake;

  setUpAll(() async {
    binding = ExplorationBinding.ensureInitialized(
      plugins: <ExplorationPlugin>[_SampleEchoPlugin()],
    )!;
    // Plugin initialization runs in a microtask; flush it so the merged
    // tool map is populated before any extension lookup.
    await Future<void>.delayed(Duration.zero);
    // The observation path runs PolicyLoop, which awaits
    // `SchedulerBinding.endOfFrame`; this test runs as a plain `test()`
    // (no widget pumping) so we inject a no-op frame-wait and a static
    // wall-clock so the loop yields without scheduling frames the host
    // will never drive. Mirrors the seam pattern used by the existing
    // observation suite.
    int now = 0;
    binding.debugSetPolicyLoopSeamsForTesting(
      waitForFrame: () async {
        now += 16;
      },
      nowMs: () => now,
    );
    fake = _BindingVmServiceFake(binding);
  });

  tearDownAll(() async {
    await fake.dispose();
  });

  test(
    'e2e: handshake returns manifest with core and sample namespaces',
    () async {
      final VmServiceClient client =
          VmServiceClient.fromVmService(fake, 'isolate-0');
      final HandshakeResult h = await client.handshake();
      expect(h.contractVersion, '1');
      final Map<String, List<String>> byNs = <String, List<String>>{
        for (final PluginManifestEntry p in h.plugins) p.namespace: p.tools,
      };
      expect(byNs.keys, containsAll(<String>['core', 'sample']));
      expect(byNs['sample'], <String>['echo']);
      expect(byNs['core'], contains('tap'));
    },
  );

  test('e2e: observation pulls a typed Observation', () async {
    final ExplorationSession session = ExplorationSession.fromVmService(
      fake,
      'isolate-0',
    );
    await session.start('test goal', const ExplorationConfig());
    final Observation obs = await session.observe();
    expect(obs, isNotNull);
  });

  test('e2e: act(sample.echo) round-trips through the envelope', () async {
    final ExplorationSession session = ExplorationSession.fromVmService(
      fake,
      'isolate-0',
    );
    await session.start('test goal', const ExplorationConfig());
    final Map<String, dynamic> r = await session.act(<String, dynamic>{
      'name': 'sample.echo',
      'args': <String, dynamic>{'text': 'hello'},
    });
    expect(r['ok'], isTrue);
    expect(r['value'], 'hello');
    expect(r['error'], isNull);
  });

  test('invokePluginTool rejects unknown tool', () async {
    expect(
      () => binding.invokePluginTool(
        'ext.flutter.exploration.sample.does_not_exist',
        const <String, String>{},
      ),
      throwsArgumentError,
    );
  });

  test('invokePluginTool rejects malformed method names', () async {
    expect(
      () => binding.invokePluginTool(
        'not.an.exploration.method',
        const <String, String>{},
      ),
      throwsArgumentError,
    );
    expect(
      () => binding.invokePluginTool(
        'ext.flutter.exploration.sample.',
        const <String, String>{},
      ),
      throwsArgumentError,
    );
  });

  test(
    'handshake on a binding-absent isolate throws BindingNotInitializedError',
    () async {
      final VmService rejecting = _RejectingVmService();
      final VmServiceClient client =
          VmServiceClient.fromVmService(rejecting, 'isolate-1');
      await expectLater(
        client.handshake(),
        throwsA(isA<BindingNotInitializedError>()),
      );
    },
  );
}
