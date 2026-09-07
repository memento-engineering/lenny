---
status: accepted
date: 2026-09-07
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: core-tap-at-is-node-relative
  surfaces:
    - "packages/leonard_flutter/lib/src/core_tools/**"
    - "packages/leonard_agent/lib/src/validation/action_validator.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: lenny-kxt9
  legacy-id: null
---
# Core coordinate taps stay node-relative

## Context

`core.tap(node_id)` preserves a deliberately strict, semantics-first contract:
it dispatches `SemanticsAction.tap` when the target supports it and otherwise
falls back to coordinate hit-testing at the node's center. A painted region
inside a semantics node can require a non-center tap without contributing a
semantics node of its own, so that interaction cannot be driven through the
live core tool surface.

The existing static tool registry and VM-service contract are influenced by
`a1-registration-composes-with-the-extension-contract-catalog`,
`a2-community-overlap-finding-adopt-dart-team-plumbing-keep-t`,
`adr-0001-declarative-perception-framework`, and
`adr-0002-perception-migration`. Those decisions guide this contract but are
not updated or obsoleted by it.

## Decision

Add a separate `core.tap_at(node_id, x, y)` tool. `x` and `y` are required,
inclusive normalized fractions in the target semantics node's logical rect:
`0` selects its left or top edge and `1` selects its right or bottom edge.
The tool always converts that node-relative point to logical coordinates and
uses the existing coordinate hit-testing path. It never dispatches a semantics
action.

Keep `core.tap(node_id)` and its schema unchanged. Register `core.tap_at` as a
separate static core tool immediately after `core.tap`, accepting one more
registry and handshake entry as the cost of preserving the original tool's
strict contract.

## Considered alternatives

- Add an optional `at_fraction` argument to `core.tap`. Rejected because it
  weakens the exact `node_id`-only schema and gives one tool two dispatch
  contracts.
- Accept explicit absolute logical coordinates. Rejected because coordinates
  detached from an observed node are fragile across viewport sizes, pixel
  ratios, layout changes, and platforms.
- Add arbitrary coordinate gestures or a new pointer synthesis path. Rejected
  because a tap needs neither the broader gesture vocabulary nor duplicate
  pointer machinery.
- Continue using `WidgetTester.tapAt` in the gauntlet. Rejected because it
  bypasses the live VM-service tool surface and cannot establish real-device
  parity.

## Consequences

Agents can tap pixels-only subregions while retaining an observed semantics
node as the target and normalization frame. Direct calls and action validation
reject missing, wrong-typed, non-finite, and out-of-range fractions rather than
clamping them. The implementation adds a stable core-tool registry entry, but
does not alter `core.tap`, observation serialization, or pointer synthesis.
