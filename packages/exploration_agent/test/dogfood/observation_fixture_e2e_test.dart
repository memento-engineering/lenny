/// End-to-end observation-fixture flow test (lenny-5tn).
///
/// Proves that when [ExplorationVmServiceFake] is constructed with a scripted
/// observation bundle, the agent-side [ExplorationSession]'s observation pull
/// returns a typed [Observation] whose contents reflect the bundle —
/// `routes` maps to `core.routeStack`, `semantics` entries map into
/// `core.nodes`, and the `Observation.toJson()` shape that
/// `AgentDogfoodHarness` records on each turn carries `node_count > 0`
/// and the fixture's route stack under `core`.
///
/// Replaces the Flutter-dependent `BindingVmServiceFake` variant written for
/// lenny-cx6.48. This file no longer imports `package:exploration_flutter`,
/// `package:flutter_test`, or `dart:ui`. The test runs under `dart test`.
///
/// Why not drive the full [AgentDogfoodHarness.run] loop here: a successful
/// turn requires a working swift-infer provider. Asserting at the
/// [ExplorationSession] seam — the same `pullObservation` call the LoopDriver
/// makes inside `_runTurnInner` step 1+2+3 — is the authoritative regression:
/// it proves the fixture flows from the fake through the agent's wire decode
/// all the way to the `core.routeStack` / `core.nodes` shape.
library;

import 'package:exploration_agent/exploration_agent.dart';
import 'package:test/test.dart';

import '../_support/exploration_vm_service_fake.dart';

// ---------------------------------------------------------------------------
// Shared fixture data
// ---------------------------------------------------------------------------

const Map<String, dynamic> _kHandshake = <String, dynamic>{
  'protocolVersion': '2',
  'plugins': <dynamic>[],
};

/// The fixture body in the binding's wire shape (top-level
/// `semantics`/`routes`/`errors`/`stability`/`plugins`, mirroring
/// what `buildCoreFragment` spreads into the response). This is the
/// shape `Observation.fromJson` consumes; [ExplorationVmServiceFake]
/// returns it verbatim under the `{type: 'Observation', value: <body>}`
/// envelope — the same contract previously held by `BindingVmServiceFake`.
const Map<String, dynamic> _kFixtureBody = <String, dynamic>{
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
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  test(
    'observation pulled through session reflects fixture: '
    'non-empty route stack and semantics nodes',
    () async {
      final ExplorationVmServiceFake fake = ExplorationVmServiceFake(
        handshakeResponse: _kHandshake,
        observationBundle: _kFixtureBody,
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
