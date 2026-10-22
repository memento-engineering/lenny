---
status: accepted
date: 2026-10-21
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: core-reports-route-layers-from-semantics
  surfaces:
    - "packages/leonard_flutter/lib/src/semantics/semantics_capture.dart"
    - "packages/leonard_flutter/lib/src/observation/core_fragment.dart"
    - "packages/leonard_flutter/lib/src/observation/core_perception.dart"
    - "packages/leonard_agent/lib/src/observation/models.dart"
    - "packages/leonard_agent/lib/src/observation/observation_differ.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: lenny-kyfdc
  legacy-id: null
---
# Core reports route layers from semantics; navigation belongs to extensions

## Context

The core observation's `routes` field (`routeStack` on the agent side) came
from `bestEffortRouteStack`: the `settings.name` of the top route of the first
`Navigator` in the element tree. That is the root navigator's top route only.
It went empty while a dialog was open (an unnamed `DialogRoute`, lenny-kyfdc),
never saw a nested navigator (a navigator per tab, a shell route), and named
nothing in apps that do not name their routes. A model reading it was told
"no route" while a modal blocked the screen.

Navigation was meant to be something apps extend: `leonard_router` takes the
app's `navigatorKey` or `routerDelegate` and reports what the app chooses to
expose. Core cannot know an app's location, path, arguments or history
without overpromising.

The framework already publishes a generic, public fact about routes on
screen: the semantics flags `scopesRoute` and `namesRoute`, which screen
readers use to announce a screen change. Page routes (`MaterialPageRoute`,
`CupertinoPageRoute`, `PageRouteBuilder`), dialogs, popup menus, bottom
sheets, drawers, dropdowns and search set `scopesRoute`; dialogs, menus,
sheets, drawers, dropdowns and search set `namesRoute` with a label. The
Material `AppBar` title names its route on platforms other than iOS and
macOS. The semantics tree omits off-stage routes and hidden tabs, and a modal
barrier hides every route beneath it.

## Decision

Core reports `route_layers`: the routes on screen, top-most last, read from
the semantics capture core already performs each observation. Each layer is
`{node, name}`: `node` is the emitted id of the node flagged `scopesRoute`,
and `name` is the label of the first node flagged `namesRoute` with a
non-empty label inside that scope (not inside a nested scope), in depth-first
paint order, which is the text a screen reader announces, or null.

One layer per route: a scope with no name and no labelled or actionable node
of its own whose only content is one nested scope is folded away, leaving
the nested layer with its own node and name. `showDialog` scopes its route
and the `AlertDialog` inside scopes itself again; that is one layer, the
`AlertDialog`'s, "Alert". Keeping the innermost node means a push of an
unnamed page inside an otherwise empty shell still changes the layer.

Layers are what the user can reach, not the route stack. A modal barrier
hides the routes beneath it from semantics, so while a dialog or modal sheet
is open it is the only layer.

The capture returns the layers with the node records from its existing walk
(`SemanticsCapture.captureSnapshotAsync`), so they always describe one
capture and observation stays pull-free. The agent parses them into `CoreFragment.routeLayers`, renders
them to the model, and diffs them (`CoreDiff.routeLayerChanges`).

Core makes no claim about navigation. Location, path, arguments and history
belong to navigation extensions such as `leonard_router`.

`routes` / `routeStack` stays, unchanged and deprecated, for five minor
releases of the owning packages: it is removed no earlier than leonard_agent
0.8.0 and leonard_flutter 0.9.0.

## Considered alternatives

- Rename `routeStack` and change its contents in one breaking release.
  Rejected by Nico in favor of a new field and a long deprecation, so
  consumers (the dogfood harness, the ACP test host, DevTools timeline,
  scripts reading `core.routeStack`) keep working.
- Fix `bestEffortRouteStack` to enumerate every navigator's routes by walking
  on-stage elements. Rejected: it still reports navigation names core cannot
  vouch for, and `Navigator` exposes no public route history to enumerate.
- Read route kinds (dialog, sheet, popup) from route types. Rejected: it
  needs the element tree and private route scope types, and a type list that
  apps' own routes would not fit.

## Consequences

The model sees a modal dialog or sheet open as the layers changing to that
dialog or sheet alone (`["Home"]` to `["Alert"]`), not as a layer added over
the page; the page returns when it closes. Nested or tabbed navigators show
only the route on screen. Names depend on the app and platform: a page with
no app bar title and a Material page on iOS or macOS are unnamed layers, and
a page whose non-pinned `SliverAppBar` title scrolls out of view loses its
name, which shows as a layer change. A new route gets a new scoping node, so
an unnamed push still changes the layer's `node`; ids are stable for a
binding's lifetime, not across sessions. When the core
budget trims semantics, each layer's node record is kept but the contents of
the top layer, at the tail, go first. Apps that relied on route names in
`routeStack` get them from a navigation extension.
