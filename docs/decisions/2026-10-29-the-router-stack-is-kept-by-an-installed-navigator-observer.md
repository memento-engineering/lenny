---
status: accepted
date: 2026-10-29
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: the-router-stack-is-kept-by-an-installed-navigator-observer
  surfaces:
    - "packages/leonard_router/lib/src/router_extension.dart"
    - "packages/leonard_router/lib/src/router_perception.dart"
    - "packages/leonard_router/lib/src/leonard_navigator_observer.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: lenny-7j5wr
  legacy-id: null
---
# The router's route stack is kept by a navigator observer the app installs

## Context

The router extension reported a route stack that it read by walking the
navigator from its top with a predicate that accepted the first route it was
handed. The walk stopped there, so the stack only ever held the top route. On
the router delegate path the extension reported the delegate's configuration
as a one-entry stack. Either way the fragment presented one route as the
navigator's history.

Flutter's navigator exposes no public route history. Observing its
notifications is the only public way to see every route on it.

## Decision

1. The route stack leonard_router reports is the one kept by a navigator
   observer the app installs, from the navigator's own push, pop, replace and
   remove notifications. The extension never infers a stack from a navigator
   or from a router delegate.
2. When no observer is installed, or no route is known, the router fragment
   carries no stack at all. An absent stack says the stack is unknown, where
   an empty or one-entry stack would claim a fact the extension does not have.
3. Without an observer the extension still reports the current route, read
   from the top of the navigator the app keyed or from the router delegate's
   configuration, and presents it only as the current route.
4. Each installed observer is reported as its own navigator, under the label
   the app gave it, in the order the app listed the observers, and the route
   names of the first fill the stack.
5. An observer never makes the router report a route on its own: whether the
   router fragment is present is decided by the current route alone.
6. Dropping the stack on the no-observer and missing-snapshot paths is a
   breaking change of the fragment, released on a new minor version of
   leonard_router. The shape that carries a stack is unchanged, so the
   committed router golden still holds.

## Why

An agent told the stack was one route acted on a history it did not have. The
observer is the resident subscription the perception framework asks for: the
navigator feeds it out of band, and the perception build stays a synchronous
read of what it holds.

## Amends

No register entry. This is the explicit compatibility decision the extension
authoring guide's versioning posture requires for removing a fragment field,
and the extension side of `lenny#2026-10-21-core-reports-route-layers-from-semantics`,
which leaves location, arguments and history to navigation extensions.

## Falsified by

- A Flutter release that exposes a navigator's route history publicly, which
  would let the extension read the stack without asking the app to install
  anything.
- An app whose navigator changes its history without notifying its observers,
  which would make the observer's stack diverge from the navigator's.
