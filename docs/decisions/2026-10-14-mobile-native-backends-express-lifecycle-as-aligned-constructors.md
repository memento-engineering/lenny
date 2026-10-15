---
status: accepted
date: 2026-10-14
decision-makers:
  - "Nico Spencer"
consulted:
  - "claude"
informed: []
register:
  spec: 1
  slug: mobile-native-backends-express-lifecycle-as-aligned-constructors
  surfaces:
    - "packages/leonard_native/lib/src/appium_capabilities.dart"
    - "packages/leonard_native/lib/src/native_backend.dart"
    - "packages/leonard_native/lib/src/native_backend_factory.dart"
    - "packages/leonard_native/lib/src/uiautomator2_backend.dart"
    - "packages/leonard_native/lib/src/xcuitest_backend.dart"
    - "packages/leonard_native/bin/leonard_native_host.dart"
    - "packages/leonard_cli/bin/leonard_drive.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: lenny-uw7i
  legacy-id: null
---

# Mobile native backends express session lifecycle as aligned constructors

## Context and Problem Statement

`mergeAppiumCapabilities` (lenny-2d9z, #37) refuses caller-supplied
attach-critical capabilities — `app`, `appPackage`, `autoLaunch`, `noReset` and
the rest — because they change whether a session installs, launches, resets or
attaches, and the backends' attach invariants depend on owning that choice: an
Android relaunch drops the `flutter run` VM-service channel the dual round-trip
needs.

GitHub #168 showed the cost. A real-device cloud grid (LambdaTest,
BrowserStack) must install and launch an uploaded app, and `UiAutomator2Backend`
has no way to do that: it only attaches, its required `app` parameter is
ignored, and the guard rejects `appium:app`. The reporter's only route nests
`appium:app` inside `lt:options`, which passes because the guard does not
recurse. The two mobile backends also disagree about what their constructors
mean: `XcuiTestBackend.new` installs and launches while `UiAutomator2Backend.new`
attaches, yet both tear off into the same function type, so
`backendForPlatform('android', app: …)` and `leonard_native_host --app` silently
attach instead of installing.

## Considered Options

* An explicit opt-in flag that bypasses the guard.
* Document vendor-option nesting as the supported route.
* A typed lifecycle per backend, with the mobile constructors aligned so the
  same constructor means the same lifecycle on every platform.

## Decision Outcome

Chosen option: **a typed lifecycle with aligned constructors.** The guard
stays; a backend sets attach-critical capabilities itself, from its
constructor, and callers never override them.

* **Launch is the unnamed constructor** on both mobile backends.
  `UiAutomator2Backend.new` installs and launches `app` (a path or a cloud app
  id), with optional `appPackage` / `appActivity`, matching
  `XcuiTestBackend.new`. Launch mode fixes `noReset: true`; there is no reset
  knob until a caller needs one.
* **Attach is `.attach`** on both, taking a shared required `appId` (the iOS
  bundle id or Android package). Each backend verifies the app is running after
  session create. `XcuiTestBackend.attach`'s `bundleId` is deprecated in favour
  of `appId`; today's Android attach moves to `UiAutomator2Backend.attach` and
  drops the unused `app`.
* **The OS version parameter is `platformVersion`** on both, sent as
  `appium:platformVersion`; iOS's `osVersion` is renamed.
* **The guard recurses into vendor option maps** (keys ending in `:options`),
  so attach-critical keys cannot be smuggled through `lt:options` and similar.
* **`backendForPlatform` and the CLI choose launch or attach explicitly**, so
  `--app` installs and launches on Android as it already does on iOS, and
  `--app-id` attaches.
* **`leonard_drive up`'s dual path attaches on both platforms.** `flutter run`
  already installs and launches the app, so the native host takes
  `--app-id <bundle id or package>` and never relaunches it; `--app` is
  removed from the dual path. Ruled by Nico in chat, 2026-10-14, over keeping
  `--app` as a deprecated no-op or deriving the id from Gradle / Xcode project
  files.

A generic bypass flag was rejected because it lets callers silently break the
attach assumptions the backends rely on, leaving lenny to support combinations
it never tests. Documenting vendor nesting was rejected because the hole is an
accident of the guard's depth, not a contract.

Ruled by Nico in chat, 2026-10-14 (option c of three: launch-only alignment,
plus the `platformVersion` rename, plus the shared `appId` attach).

### Consequences

* Good, because a constructor tear-off now means the same lifecycle on iOS and
  Android, so the factory and CLI select by tear-off rather than rebuilding
  arguments per platform.
* Good, because cloud grids get a supported install-and-launch path without
  weakening the guard.
* Bad, because it is a breaking change to `leonard_native` (0.5.0): Android's
  unnamed constructor changes meaning, and iOS's `osVersion` / `bundleId`
  parameters are renamed. `leonard_drive up --app` is breaking for
  `leonard_cli` too (0.4.0-dev.1).
* Bad, because the reporter's nested `lt:options.app` workaround stops working
  in the same release that gives them the supported path.
