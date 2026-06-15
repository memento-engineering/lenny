/// Regression test for lenny-cx6.46 (originally agent-side; moved to
/// leonard_flutter under lenny-imr alongside the hoisted fake).
///
/// Proves that [BindingVmServiceFake] routes by
/// `extensionRegistry.mergedTools()` and not by the literal
/// `ext.exploration.core.*` URL prefix:
///
///   - a plugin registered under namespace `core` (deliberately
///     reusing the namespace that previously triggered the routing
///     bug) is reached via `invokeExtensionTool`;
///   - a binding-owned extension (`core.get_stable_observation`),
///     which is NOT in `mergedTools()`, falls through to
///     `invokeServiceExtension`;
///   - any method that does not start with
///     `ext.exploration.` still throws
///     `RPCError(..., -32601, ...)`.
///
/// Fixture-serving paths (lenny-cx6.48) are also covered, using a
/// file-local minimal duck-typed body holder (`_FakeFixture`) instead
/// of `package:leonard_agent/src/dogfood/observation_fixture.dart`
/// — leonard_flutter cannot depend on leonard_agent, and the
/// fake reads `body` via `dynamic` dispatch so any class exposing the
/// getter works.
library;

import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:leonard_flutter/test_support/binding_vm_service_fake.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart';

/// Minimal duck-typed body holder for the fake's fixture-serving
/// branch. The fake reads `body` via `dynamic` dispatch so any class
/// exposing this getter works; the production-side `ObservationFixture`
/// in `package:leonard_agent/src/dogfood/observation_fixture.dart`
/// is one such class, but leonard_flutter cannot depend on it.
class _FakeFixture {
  _FakeFixture(this.body);
  final Map<String, dynamic> body;
}

class _CoreNamespaceTapTool extends LeonardTool {
  _CoreNamespaceTapTool();

  bool invoked = false;
  Map<String, Object?>? lastArgs;

  @override
  String get name => 'tap';

  @override
  String get description => 'core.tap stand-in for routing regression';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'x': <String, Object?>{'type': 'number'},
          'y': <String, Object?>{'type': 'number'},
        },
      });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    invoked = true;
    lastArgs = Map<String, Object?>.from(args);
    return const ToolResult(ok: true, value: 'tapped');
  }
}

class _CoreNamespaceExtension extends LeonardExtension {
  _CoreNamespaceExtension(this.tap);

  final _CoreNamespaceTapTool tap;

  @override
  String get namespace => 'core';

  @override
  List<LeonardTool> get tools => <LeonardTool>[tap];

  @override
  Future<void> initialize(ExtensionContext ctx) async {}


  @override
  Future<BusyState> busyState() async => BusyState.idle;

  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  late LeonardBinding binding;
  late _CoreNamespaceTapTool tap;
  late BindingVmServiceFake fake;

  setUpAll(() async {
    tap = _CoreNamespaceTapTool();
    binding = LeonardBinding.ensureInitialized(
      extensions: <LeonardExtension>[_CoreNamespaceExtension(tap)],
      installCoreExtension: false,
    )!;
    // Plugin initialization runs in a microtask; flush it so the merged
    // tool map is populated before the fake's first lookup.
    await Future<void>.delayed(Duration.zero);
    // PolicyLoop awaits `SchedulerBinding.endOfFrame`; this test runs
    // as a plain `test()` with no widget pumping, so inject a no-op
    // frame-wait and a static wall-clock to let the binding-owned
    // `core.get_stable_observation` path terminate without scheduling
    // frames the host will never drive.
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
    await LeonardBinding.debugReset();
  });

  test(
    'core.tap routes via extensionRegistry.mergedTools -> invokeExtensionTool',
    () async {
      final Response r = await fake.callServiceExtension(
        'ext.exploration.core.tap',
        args: <String, dynamic>{'x': 0.1, 'y': 0.2},
      );
      expect(tap.invoked, isTrue,
          reason: 'plugin tool must be reached when its <ns>.<tool> '
              'suffix is in mergedTools()');
      expect(tap.lastArgs, <String, Object?>{'x': 0.1, 'y': 0.2});
      expect(r.json!['ok'], isTrue);
      expect(r.json!['value'], 'tapped');
    },
  );

  test(
    'core.get_stable_observation (binding-owned, not in mergedTools) '
    'falls through to invokeServiceExtension',
    () async {
      final Response r = await fake.callServiceExtension(
        'ext.exploration.core.get_stable_observation',
      );
      // The binding-owned extension wraps the result in
      // `{type: 'Observation', value: <bundle>}`; the plugin envelope
      // would have shape `{ok, value, error}`. Asserting on `type`
      // proves we reached `invokeServiceExtension`, not
      // `invokeExtensionTool`.
      expect(r.json!['type'], 'Observation',
          reason: 'binding-owned observation envelope must come from '
              'invokeServiceExtension, not the plugin path');
      expect(r.json!.containsKey('value'), isTrue);
    },
  );

  test('unknown prefix throws RPCError -32601', () async {
    expect(
      () => fake.callServiceExtension('ext.dart.io.read'),
      throwsA(isA<RPCError>().having(
        (RPCError e) => e.code,
        'code',
        -32601,
      )),
    );
  });

  group('observation fixture serving (lenny-cx6.48)', () {
    test(
      'returns fixture body wrapped in Observation envelope when '
      'fixture is supplied',
      () async {
        final Map<String, dynamic> body = <String, dynamic>{
          'core': <String, dynamic>{
            'routeStack': <String>['login'],
            'nodes': <String, dynamic>{
              'n1': <String, dynamic>{
                'id': 'n1',
                'label': 'Email',
                'rect': <double>[0, 0, 100, 40],
              },
            },
          },
          'extensions': <String, dynamic>{},
          'stability': <String, dynamic>{'policy': 'action_relative'},
        };
        final _FakeFixture fixture = _FakeFixture(body);
        final BindingVmServiceFake fixtureFake = BindingVmServiceFake(
          binding,
          observationFixture: fixture,
        );

        final Response r = await fixtureFake.callServiceExtension(
          'ext.exploration.core.get_stable_observation',
          args: <String, dynamic>{'policy': 'action_relative'},
        );

        expect(r.json, isNotNull);
        expect(r.json!['type'], 'Observation');
        expect(r.json!['value'], body);
      },
    );

    test(
      'fixture short-circuit does not affect other extension routes — '
      'plugin tool still reaches invokeExtensionTool',
      () async {
        // Reuse the `core.tap` plugin tool wired in setUpAll. Construct
        // a fixture-armed fake and prove the fixture is irrelevant for
        // non-observation methods: `core.tap` still routes via the
        // registry and the plugin's `tap.call` runs.
        tap.invoked = false;
        tap.lastArgs = null;
        final _FakeFixture fixture = _FakeFixture(<String, dynamic>{
          'core': <String, dynamic>{'routeStack': <String>['login']},
        });
        final BindingVmServiceFake fixtureFake = BindingVmServiceFake(
          binding,
          observationFixture: fixture,
        );

        final Response r = await fixtureFake.callServiceExtension(
          'ext.exploration.core.tap',
          args: <String, dynamic>{'x': 0.5, 'y': 0.5},
        );

        expect(tap.invoked, isTrue,
            reason: 'fixture short-circuit must NOT intercept other '
                'methods; core.tap must still route via mergedTools');
        expect(tap.lastArgs, <String, Object?>{'x': 0.5, 'y': 0.5});
        expect(r.json!['ok'], isTrue);
      },
    );

    test(
      'without a fixture, get_stable_observation still falls through '
      'to the binding (existing behavior preserved)',
      () async {
        // Construct a fresh fake with NO fixture. The call must still
        // return the binding's `{type: 'Observation', value: <bundle>}`
        // envelope from invokeServiceExtension — proving the constructor
        // default preserves today's behavior. (The `setUpAll` `fake`
        // also has no fixture; we use a local instance here to make the
        // test self-contained.)
        final BindingVmServiceFake noFixtureFake =
            BindingVmServiceFake(binding);
        final Response r = await noFixtureFake.callServiceExtension(
          'ext.exploration.core.get_stable_observation',
        );
        final Map<String, dynamic> envelope = r.json!;
        expect(envelope['type'], 'Observation');
        expect(envelope.containsKey('value'), isTrue);
        // The real binding's empty-tree response: the fixture body's
        // 'login' route stack must NOT appear here. We assert the
        // observation came from the binding, not from a leaked fixture.
        final Map<String, dynamic> bundle =
            (envelope['value'] as Map).cast<String, dynamic>();
        final Map<String, dynamic>? core =
            (bundle['core'] as Map?)?.cast<String, dynamic>();
        final Object? routeStack = core?['routeStack'];
        // The binding's empty-tree response either omits routeStack or
        // returns an empty list; in particular it must not be ['login'].
        if (routeStack is List) {
          expect(routeStack, isNot(<String>['login']));
        }
      },
    );
  });
}
