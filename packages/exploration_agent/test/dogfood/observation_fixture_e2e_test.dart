/// End-to-end observation-fixture flow test (lenny-cx6.48).
///
/// Proves that when [BindingVmServiceFake] is constructed with an
/// [ObservationFixture], the agent-side [ExplorationSession]'s
/// observation pull returns a typed [Observation] whose contents
/// reflect the fixture — top-level `routes` map to `core.routeStack`,
/// top-level `semantics` entries map into `core.nodes`, and the
/// `Observation.toJson()` shape that `AgentDogfoodHarness` records on
/// each turn carries `node_count > 0` and the fixture's route stack
/// under `core`.
///
/// This file complements `test/_support/binding_vm_service_fake_test.dart`:
/// that test asserts the wire-level short-circuit (fixture body wrapped
/// in the binding's `{type: 'Observation', value: <body>}` envelope);
/// this test asserts the agent-side decode of that envelope through
/// `ExplorationSession.pullObservation()` and into the
/// `Observation.toJson()` shape that feeds
/// `AgentDogfoodHarness._observationSummary`.
///
/// Why not drive the full [AgentDogfoodHarness.run] loop here: a
/// successful turn requires a working swift-infer provider (the harness
/// constructs its own [SwiftInferModelProvider] internally with no
/// `http.Client` injection seam). On a failed turn the LoopDriver
/// writes `_prev.toJson()` as the observation, and on turn 0 `_prev` is
/// [Observation.empty()] — so a hung-provider failed-turn path masks
/// the fixture even after the fixture is correctly served. Asserting at
/// the [ExplorationSession] seam — the same `pullObservation` call the
/// LoopDriver makes inside `_runTurnInner` step 1+2+3 — is the
/// authoritative cx6.48 regression: it proves the fixture flows from
/// the binding fake through the agent's wire decode all the way to the
/// `core.routeStack` / `core.nodes` shape the `_observationSummary`
/// helper projects.
library;

import 'package:exploration_agent/exploration_agent.dart';
import 'package:exploration_agent/src/dogfood/observation_fixture.dart';
import 'package:exploration_flutter/exploration_flutter.dart';
import 'package:exploration_flutter/test_support/binding_vm_service_fake.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ExplorationBinding binding;

  setUpAll(() async {
    binding = ExplorationBinding.ensureInitialized(
      plugins: const <ExplorationPlugin>[],
      installCorePlugin: false,
    )!;
    await Future<void>.delayed(Duration.zero);
    int now = 0;
    binding.debugSetPolicyLoopSeamsForTesting(
      waitForFrame: () async {
        now += 16;
      },
      nowMs: () => now,
    );
  });

  tearDownAll(() async {
    await ExplorationBinding.debugReset();
  });

  test(
    'observation pulled through session reflects fixture: '
    'non-empty route stack and semantics nodes',
    () async {
      // Fixture body in the binding's wire shape (top-level
      // `semantics`/`routes`/`errors`/`stability`/`plugins`, mirroring
      // what `buildCoreFragment` spreads into the response). This is
      // the shape `Observation.fromJson` consumes; the
      // `BindingVmServiceFake` returns it verbatim under the
      // `{type: 'Observation', value: <body>}` envelope.
      final ObservationFixture fixture =
          ObservationFixture.forTest('<test>', <String, dynamic>{
        'semantics': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 1,
            'role': 'textfield',
            'label': 'Email',
            'rect': <int>[0, 0, 100, 40],
          },
          <String, dynamic>{
            'id': 2,
            'role': 'textfield',
            'label': 'Password',
            'rect': <int>[0, 50, 100, 90],
          },
          <String, dynamic>{
            'id': 3,
            'role': 'button',
            'label': 'Sign in',
            'rect': <int>[0, 100, 100, 140],
          },
        ],
        'routes': <String>['login'],
        'errors': <Map<String, dynamic>>[],
        'stability': <String, dynamic>{
          'policy': 'action_relative',
          'reason': 'idle',
        },
        'plugins': <String, dynamic>{},
      });

      final BindingVmServiceFake fake = BindingVmServiceFake(
        binding,
        observationFixture: fixture,
      );
      final ExplorationSession session =
          ExplorationSession.fromVmService(fake, 'isolate-0');
      await session.start('sign in', const ExplorationConfig());
      try {
        final Observation curr = await session.pullObservation(
          policy: StabilityPolicy.actionRelative,
        );

        // Typed observation: the fixture's `routes` and `semantics`
        // round-tripped into the agent's CoreFragment.
        expect(
          curr.core.routeStack,
          <String>['login'],
          reason: 'fixture `routes` must surface as core.routeStack',
        );
        expect(curr.core.nodes.length, 3,
            reason: 'fixture `semantics` entries must map into '
                'core.nodes keyed by id');
        expect(curr.core.nodes.keys.toSet(), <int>{1, 2, 3});
        expect(curr.core.nodes[3]!.label, 'Sign in');

        // `Observation.toJson()` is exactly what `TurnRecord.observation`
        // carries on a successful turn and what
        // `_observationSummary(t)` reads from. Assert the shape the
        // dogfood trace's `observation_summary` projects.
        final Map<String, dynamic> obs = curr.toJson();
        final Map<String, dynamic> core =
            (obs['core'] as Map).cast<String, dynamic>();
        expect(core['routeStack'], <String>['login']);
        // `CoreFragment.toJson` serialises nodes as a Map keyed by
        // node-id strings; `_observationSummary` counts Map entries.
        final Map<String, dynamic> nodes =
            (core['nodes'] as Map).cast<String, dynamic>();
        expect(nodes.length, 3,
            reason: 'observation_summary.node_count would be 3 — '
                'matching the fixture');
      } finally {
        await session.end();
      }
    },
  );
}
