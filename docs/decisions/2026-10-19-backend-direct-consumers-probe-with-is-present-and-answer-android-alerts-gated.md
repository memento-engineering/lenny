---
status: accepted
date: 2026-10-19
decision-makers:
  - "Nico Spencer"
consulted:
  - "claude"
informed: []
register:
  spec: 1
  slug: backend-direct-consumers-probe-with-is-present-and-answer-android-alerts-gated
  surfaces:
    - "packages/leonard_native/lib/src/native_backend.dart"
    - "packages/leonard_native/lib/src/native_snapshot.dart"
    - "packages/leonard_native/lib/src/xcuitest_backend.dart"
    - "packages/leonard_native/lib/src/uiautomator2_backend.dart"
    - "packages/leonard_native/lib/src/mac2_backend.dart"
    - "packages/leonard_native/lib/src/fake_native_backend.dart"
    - "packages/leonard_native/lib/src/native_extension.dart"
  obsoletes: []
  updates:
    - "native-backend-serves-backend-direct-consumers-alerts-focus-and-probes"
  obsoleted-by: null
  updated-by: []
  bead: lenny-4bni
  legacy-id: null
---

# Backend-direct consumers probe with isPresent and answer Android alerts gated

## Context and Problem Statement

The same consumer filed nine more `leonard_native` gaps (GitHub #185 to #193).
Reviewing PR 184 against its own suite, it also found that the earlier ruling's
presence probe misleads: `resolve(..., findTimeout: Duration.zero)` still falls
back to rect-center from the selector's rect or a cached label match, so a
probe that reuses its snapshot reports a gone element as present, silently.
Several of the new asks offered more than one shape.

## Decision Outcome

* **A presence probe is `isPresent(selector)`, not a zero-timeout `resolve`.**
  One live find per populated tier, no retry, never a rect. `resolve` keeps its
  rect-center fallback (it serves tapping) and `findTimeout` stays for callers
  that poll in their own loop. This amends the earlier ruling, which made the
  timeout the probe.
* **`isPresent`'s label tier is a live query** on the platform's label
  attributes (iOS `label` or `name`, Android `text` or `content-desc`, macOS
  `label` or `title`), not a cached-snapshot lookup, so a stale positional
  xpath can never match a different element.
* **Android answers system alerts, gated.** `press('consent_accept')`,
  `press('alert_dismiss')` and the new `acceptAlertIfPresent` /
  `dismissAlertIfPresent` post the W3C alert endpoint on Android too, refusing
  a runtime permission dialog (accept grants, dismiss denies: a persistent
  change only `permission_allow` / `permission_deny` may make), and failing
  closed when the source cannot be read. Keeping them iOS-only would have left
  Android able to read a dialog but not answer it.
* **`rawSource()` plus the `disabled` state on iOS and macOS**, not an
  unfiltered snapshot mode: inspectors get the unparsed document, and the
  observation gains only a state Android already reports.
* **`readAttribute` takes a resolved `NativeTarget`**, like `tap` and
  `enterText`, so the caller chooses the lookup timeout and reads several
  attributes from one handle.
* **One breaking release.** `leonard_native` 0.6.0-dev.1, still unpublished,
  takes all of #180 to #193, rather than publishing 0.6 and following with 0.7.

Ruled by Nico in chat, 2026-10-19: release, `rawSource`, `readAttribute`, the
`isPresent` shape and its label tier on the recommended options; Android alerts
after asking why Android should be left out ("are we leaving a gap?").

### Consequences

* Good, because a probe written the obvious way can no longer answer wrong.
* Good, because Android consumers can read and answer system dialogs through
  the seam, without bypassing the permission policy.
* Bad, because the seam grows again, breaking every implementer and every
  `FakeNativeBackend` subclass that overrides `resolve` or `enterText`.
