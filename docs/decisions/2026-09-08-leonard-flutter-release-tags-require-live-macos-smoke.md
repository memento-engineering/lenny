---
status: accepted
date: 2026-09-08
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: leonard-flutter-release-tags-require-live-macos-smoke
  surfaces:
    - ".github/workflows/publish.yml"
    - "pubspec.yaml"
    - "packages/leonard_cli/tool/live_macos_smoke.dart"
    - "packages/leonard_cli/test/ci/release_live_smoke_wiring_test.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: lenny-v1l8
  legacy-id: null
---

# Leonard Flutter release tags require a live macOS smoke

## Context and Problem Statement

Unit tests, widget tests, and source inspection do not prove that Leonard's
public VM-service capabilities work against a booted application. In
particular, the `leonard_flutter-v0.4.0-rc.1` screenshot implementation passed
its existing evidence while a real external capture failed with
`inspector_unavailable`.

An `integration_test` binding is not the right substrate for this proof.
Flutter permits one binding per application, and `LeonardBinding` cannot be
installed alongside `IntegrationTestWidgetsFlutterBinding`. A normal
`LeonardBinding` application driven externally over the VM service avoids that
one-binding conflict.

## Decision Outcome

A `leonard_flutter-v*` tag may publish only after a non-skipping macOS smoke
boots the workspace's normal sample app and uses Leonard's external driver to
validate real semantics output and a decoded PNG screenshot. The semantics
tree must contain the expected gauntlet label. The screenshot must have the PNG
signature, non-trivial byte size, positive decoded dimensions, and dimensions
equal to the driver's reported metadata.

The tag-triggered publish workflow therefore requires the live macOS result to
be exactly `success` before either publishing path can run. Tags for other
packages retain their existing release path and accept the live job's
intentional skipped result. The default pull-request workflow does not run this
desktop boot lane.

The known `leonard_flutter-v0.4.0-rc.1` failure is the falsifying negative
control: running the same smoke against that target must report
`inspector_unavailable` and must not emit a pass receipt.

### Consequences

* Good, because a screenshot or semantics rewrite cannot ship solely on
  self-referential source checks or isolated tests.
* Good, because the proof exercises the public VM-service firewall without
  changing application bindings or capture production.
* Bad, because Flutter release tags pay for a macOS desktop boot and an
  additional required CI job.
