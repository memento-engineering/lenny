---
status: accepted
date: 2026-11-17
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: the-publish-workflow-guards-every-tag-before-it-publishes
  surfaces:
    - ".github/workflows/publish.yml"
    - "tool/publish_guard.sh"
    - "tool/publish_guard_test.sh"
    - "packages/leonard_cli/test/ci/release_live_smoke_wiring_test.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: lenny-xn84u
  legacy-id: null
---

# The publish workflow guards every tag before it publishes

## Context and Problem Statement

`memento-engineering#a-release-is-a-bump-pr-then-a-guarded-tag-push` rules
that a release tag is pushed only after its pubspec is checked against it, and
that a dependent package's tag waits until the tag it depends on has published.
Both checks live in the command that pushes the tag. A tag pushed by any other
route, by hand or from another tool, reaches the publish workflow unchecked,
and the workflow publishes whatever the tagged commit holds. A mis-tagged
version, a release without its changelog heading, or a dependent published
ahead of its sibling all reach pub.dev, where a version cannot be withdrawn.

## Decision Outcome

Every release tag passes a guard in the publish workflow before the shared
release gate opens any publishing path. The guard refuses the tag unless three
things hold. The package's pubspec at the tagged commit reads the tag's
version. Its changelog has a heading for that version. Each sibling package it
names as a runtime dependency has, listed on pub.dev, the version that
sibling's own pubspec declares at the tagged commit.

The guard fails closed. A pub.dev listing it cannot read, or a dependency list
it cannot parse, refuses the tag.

Dependency readiness is judged against the sibling's declared version at the
tagged commit, not against the dependent's constraint. Under the org rule a
sibling's version changes only in its release pull request, so a declared
version missing from pub.dev means that sibling's tag has not published, and
the dependent must wait for it.

Development dependencies are not checked, because they never reach a
consumer's resolution.

The guard reads pub.dev only, because no package of this repository is
tag-distributed. A tag-distributed sibling requires this entry amended.

The check names, the lines the guard prints and its parse rules live in
`tool/publish_guard.sh`.

Why: this is the publishing-side enforcement of items 3 and 5 of
`memento-engineering#a-release-is-a-bump-pr-then-a-guarded-tag-push`. A tag
pushed by any route is checked, while the station's release command checks
before it pushes. It composes with
`lenny#leonard-flutter-release-tags-require-live-macos-smoke` and amends
nothing.

This is falsified when a tag publishes whose pubspec does not read its version,
or whose sibling's declared version was not on pub.dev when it published.

### Consequences

* Good, because a tag pushed by hand is held to the same checks as one the
  release command pushes.
* Good, because a dependent tag pushed too early fails before it publishes,
  and can be re-run once its sibling is on pub.dev.
* Bad, because every release tag now pays for one more job and reads pub.dev,
  so a pub.dev outage blocks publishing until it recovers.
