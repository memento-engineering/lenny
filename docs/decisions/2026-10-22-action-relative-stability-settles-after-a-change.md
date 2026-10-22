---
status: accepted
date: 2026-10-22
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: action-relative-stability-settles-after-a-change
  surfaces:
    - "packages/leonard_flutter/lib/src/observation/policy_loop.dart"
    - "packages/leonard_flutter/lib/src/observation/observation_request.dart"
    - "packages/leonard_flutter/lib/src/observation/stability_metadata.dart"
    - "packages/leonard_agent/lib/src/observation/models.dart"
    - "packages/leonard_agent/lib/src/multi_host/observation_merge.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: lenny-r1k2x
  legacy-id: null
---
# Action-relative stability settles after a change

## Context

`action-relative`, the default stability policy, ended the observation wait on
the first of: a route change, a semantics change, the framework and every
extension idle, or 800 ms. The first two only show that the action had an
effect. They say nothing about whether the result has finished appearing.

On a live drive on 2026-10-22 (iPad mini, sample app, typed login), the push
to the home route changed the route hash on its first frame while the page
transition was still animating. The wait ended after 267 ms with nine
transient callbacks running, and the observation held two unlabelled
full-screen containers and no route layers. The agent called `core.done` on the
route name alone. The same step on a Pixel 7a happened to end on the 800 ms
budget and saw the finished home screen.

The framework already reports when it is quiet: no transient callbacks and no
pending microtasks, sampled every frame. The `quiet-frame` and
`bounded-stability` policies wait for that. `action-relative` was the only
policy that did not.

## Decision

Under `action-relative`, a route or semantics change starts a settle instead
of ending the wait. The settle ends after `quietFrameN` consecutive frames in
which the framework and every extension are idle, or when
`actionRelativeSettleBudgetMs` has elapsed since the start of the observation.
The budget defaults to 1500 ms, is clamped like the other budgets, and is never
below `actionRelativeBudgetMs`.

`terminated_by` keeps naming the change that started the settle
(`route_change`, or `semantics_change` unless a route change follows), so the
trigger is still visible. A new `settled` boolean in the stability block says
whether the app was quiet at the end: true for a completed settle, `idle` and
`quiet_frame`; false when a budget ran out first. The agent model carries it as
nullable (older hosts do not send it), trajectories record it, and the
multi-host merge reports false if any host is unsettled.

With no change during the wait, `action-relative` behaves as before: it ends on
idle or at 800 ms.

## Considered alternatives

- Make `bounded-stability` the default. Rejected: it waits for quiet frames
  even when nothing changed, and the CLI and tools already depend on
  `action-relative` returning promptly after an action that has no visible
  effect.
- Wait a fixed delay after a route change. Rejected: transitions vary in
  length by platform and route type, and the framework already reports when
  they end.
- End on the change, but flag the observation as unsettled. Rejected: the agent
  would still act on a half-built screen, and the fix is cheap.

## Consequences

An action that changes the route or the semantics tree now returns once the
screen has stopped animating, typically one transition (about 300 to 500 ms)
later than before, and at most 1.5 s after the observation started. An app that
never goes quiet, with a spinner or a looping animation, returns at the settle
budget with `settled: false`, which is no worse than before and is now
visible to the model and in trajectories.
