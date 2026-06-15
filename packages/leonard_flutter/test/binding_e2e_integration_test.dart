/// End-to-end integration test for the agent ↔ binding wire contract
/// (parent epic lenny-cvl).
///
/// Boots a real [LeonardBinding] with the host-installed [CoreExtension]
/// plus a test-local `_SampleEchoExtension` and drives
/// handshake → observation → tool call through the agent's
/// [VmServiceClient] / [LeonardSession]. The siblings lenny-cvl.1–3
/// reconciled the three surfaces independently; this test exercises all
/// three at once against the same binding so future drift between the
/// agent and the binding cannot ship undetected.
library;

import 'dart:async';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:leonard_flutter/test_support/binding_vm_service_fake.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart';

/// Tool contributed by [_SampleEchoExtension]: returns the `text` argument
/// verbatim wrapped in a successful [ToolResult].
class _EchoTool extends LeonardTool {
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
/// `invokeExtensionTool` → `mergedTools()['sample.echo']` seam, which is
/// the deliberate test-only path documented on
/// [LeonardBinding.invokeExtensionTool]. Plugin tools register their
/// VM service extensions via `dart:developer.registerExtension`
/// directly from inside [CoreExtension.initialize] (see
/// `core_plugin_registration_test.dart`); this test exists precisely
/// to cover the in-process wire-contract dispatch without a live VM.
class _SampleEchoExtension extends LeonardExtension {
  @override
  String get namespace => 'sample';
  @override
  List<LeonardTool> get tools => const <LeonardTool>[_EchoTool()];
  @override
  Future<void> initialize(ExtensionContext ctx) async {}
  @override
  Future<BusyState> busyState() async => BusyState.idle;
  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}
  @override
  Future<void> dispose() async {}
}

/// Stand-in VmService whose `callServiceExtension` unconditionally
/// raises the JSON-RPC "method not found" error — what a live VM would
/// emit if the target isolate has no `LeonardBinding` installed.
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
  late LeonardBinding binding;
  late BindingVmServiceFake fake;

  setUpAll(() async {
    binding = LeonardBinding.ensureInitialized(
      plugins: <LeonardExtension>[_SampleEchoExtension()],
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
    fake = BindingVmServiceFake(binding);
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
      expect(h.contractVersion, '2');
      final Map<String, List<String>> byNs = <String, List<String>>{
        for (final ExtensionManifestEntry p in h.plugins) p.namespace: p.tools,
      };
      expect(byNs.keys, containsAll(<String>['core', 'sample']));
      expect(byNs['sample'], <String>['echo']);
      expect(byNs['core'], contains('tap'));
    },
  );

  test('e2e: observation pulls a typed Observation', () async {
    final LeonardSession session = LeonardSession.fromVmService(
      fake,
      'isolate-0',
    );
    await session.start('test goal', const LeonardConfig());
    final Observation obs = await session.observe();
    expect(obs, isNotNull);
  });

  test('e2e: act(sample.echo) round-trips through the envelope', () async {
    final LeonardSession session = LeonardSession.fromVmService(
      fake,
      'isolate-0',
    );
    await session.start('test goal', const LeonardConfig());
    final Map<String, dynamic> r = await session.act(<String, dynamic>{
      'name': 'sample.echo',
      'args': <String, dynamic>{'text': 'hello'},
    });
    expect(r['ok'], isTrue);
    expect(r['value'], 'hello');
    expect(r['error'], isNull);
  });

  test('invokeExtensionTool rejects unknown tool', () async {
    expect(
      () => binding.invokeExtensionTool(
        'ext.exploration.sample.does_not_exist',
        const <String, String>{},
      ),
      throwsArgumentError,
    );
  });

  test('invokeExtensionTool rejects malformed method names', () async {
    expect(
      () => binding.invokeExtensionTool(
        'not.an.exploration.method',
        const <String, String>{},
      ),
      throwsArgumentError,
    );
    expect(
      () => binding.invokeExtensionTool(
        'ext.exploration.sample.',
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
