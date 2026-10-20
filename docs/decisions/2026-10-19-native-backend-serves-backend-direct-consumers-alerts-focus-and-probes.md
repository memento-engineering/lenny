---
status: accepted
date: 2026-10-19
decision-makers:
  - "claude"
consulted: []
informed:
  - "Nico Spencer"
register:
  spec: 1
  slug: native-backend-serves-backend-direct-consumers-alerts-focus-and-probes
  surfaces:
    - "packages/leonard_native/lib/src/native_backend.dart"
    - "packages/leonard_native/lib/src/xcuitest_backend.dart"
    - "packages/leonard_native/lib/src/uiautomator2_backend.dart"
    - "packages/leonard_native/lib/src/mac2_backend.dart"
    - "packages/leonard_native/lib/src/fake_native_backend.dart"
  obsoletes: []
  updates:
    - "mobile-native-backends-express-lifecycle-as-aligned-constructors"
  obsoleted-by: null
  updated-by:
    - backend-direct-consumers-probe-with-is-present-and-answer-android-alerts-gated
  bead: lenny-5lew
  legacy-id: null
---

# NativeBackend serves backend-direct consumers: alerts, focus and probes

## Context and Problem Statement

A consumer driving real iOS sign-in flows through `NativeBackend` keeps a
hand-rolled XCUITest transport beside `leonard_native` for four things the seam
cannot do (GitHub #180 to #183, beads lenny-5lew, lenny-7dvw, lenny-pmip,
lenny-uphh): read an open alert's text, bring the app under test back to the
foreground, probe for an element without a ~10 s retry per miss, and attach
without the session activating the app. Each issue offered a choice of shape.

## Decision Outcome

* **Presence probes are a `findTimeout` on `resolve`, not a new `isPresent`.**
  `resolve(selector, cached, {findTimeout = NativeBackend.defaultFindTimeout})`
  sets each populated tier's find window, and `Duration.zero` is one request
  per tier. It keeps one resolution chain instead of a second lookup with its
  own tier rules, and it serves both a probe and a caller that polls in its
  own loop. The name says per find, because the window is per tier, not a
  total.
* **`alertText()` returns null only for "no alert".** iOS and Android map W3C
  `no such alert` to null; any other failure, an unsupported driver included,
  is a `NativeException`. macOS throws with the W3C `unsupported operation`
  code, because a macOS alert is an ordinary window in the snapshot and null
  would claim none is open.
* **`activateApp(appId)` is on every backend**, issuing the driver's own
  `activateApp` (`mobile:` on iOS and Android, `macos:` on macOS).
* **iOS attach sends `appium:autoLaunch: false` unconditionally, not as an
  opt-in.** Attach means "drive the running app without touching its
  lifecycle" on both platforms (2026-10-14); activating it was the asymmetry.
  A caller that wants it forward calls `activateApp`.
* **A suspended background iOS app is running.** Measured live (iOS 27.0
  simulator, XCUITest driver 12.18.1): with attach no longer activating it, a
  backgrounded Settings reports `queryAppState` 2, so the attach check fails
  only on 0 and 1, and its message names both causes of a 1.

This amends the 2026-10-14 lifecycle decision, which stays in force: iOS attach
now leaves the app where it is, as Android attach already did.

### Consequences

* Good, because the consumer can retire its hand-rolled transport, and a probe
  that misses costs tens of milliseconds instead of ~10 s.
* Bad, because adding abstract members and a `resolve` parameter breaks every
  class that implements `NativeBackend` or overrides
  `FakeNativeBackend.resolve`, so `leonard_native` takes a minor bump
  (0.6.0-dev.1).
* Bad, because code that relied on iOS attach bringing the app to the front
  must now call `activateApp` after `connect()`.
