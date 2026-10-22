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
which the framework and every extension are idle; the frame that shows the
change counts as the first. Once started, a settle runs to its end even if the
change reverts.

Its cap depends on the change. A route change may settle until
`actionRelativeSettleBudgetMs` has elapsed since the observation started: a new
request field, default 1500 ms, clamped like the other budgets and never below
`actionRelativeBudgetMs`. A semantics-only change settles within
`actionRelativeBudgetMs` (800 ms), because the semantics hash covers node
rects: an app that animates forever (a carousel, a marquee, a shimmer, a
fling) changes it every frame, and must cost no more than a wait in which
nothing changed. A route change during a semantics settle extends it to the
route cap.

`terminated_by` keeps naming the change that started the settle
(`route_change`, or `semantics_change` unless a route change follows), so the
trigger is still visible. A new `settled` boolean in the stability block says
whether the app was quiet at the end: true for a completed settle, `idle` and
`quiet_frame`; false when a budget ran out first. The agent model carries it as
nullable (older hosts do not send it), trajectories record it, and the
multi-host merge reports false if any host is unsettled.

The loop races every frame wait with the active budget. `endOfFrame` never
completes while frames are off (the app hidden, paused or detached, as when an
action opens an external URL or a native sign-in sheet), so before this the
observation could outlast any budget.

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

An action that changes the route now returns once the screen has stopped
animating, typically one transition (about 300 to 500 ms) later than before,
and at most 1.5 s after the observation started.

The cost falls on apps that never go quiet. Before, any change ended the wait
within about a frame. Now a semantics change in such an app waits up to the
800 ms action budget, and a route change up to 1.5 s, before returning with
`settled: false`. That is the price of not acting on a half-built screen, and
the flag makes it visible to the model and in trajectories. The 800 ms bound
for semantics-only changes keeps it at the cost of a no-change wait.
