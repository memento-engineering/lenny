---
status: accepted
date: 2026-09-18
decision-makers:
  - "Nico Spencer"
consulted:
  - "governor"
informed: []
register:
  spec: 1
  slug: the-macos-native-backend-drives-through-appium-mac2
  surfaces:
    - "packages/leonard_native/lib/src/native_backend.dart"
    - "packages/leonard_native/lib/src/native_backend_factory.dart"
    - "packages/leonard_native/lib/src/appium_capabilities.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: lenny-sihl
  legacy-id: null
---

# The macOS native backend drives through Appium mac2

## Context and Problem Statement

lenny-1ank (the macOS backend epic) needs a `NativeBackend` that perceives a
Flutter desktop app's accessibility tree — and the system alert sheets layered
over it — and drives the four native tools plus permission_allow /
permission_deny. The epic left the driver open: an Appium mac2 session (XCTest
for macOS, the shape of the iOS XCUITest backend) or a direct AX client (a Dart
FFI or Swift helper with its own connect() and snapshot source). The fork sets
the whole plan — capabilities entry versus a new process, one parser versus a
new snapshot source, Appium in the harness or not — and the spec-readiness lens
held lenny-1ank.1 on it (epoch 88, 2026-09-18).

## Decision Outcome

The macOS `NativeBackend` is an **Appium mac2** driver: `automationName: Mac2`,
bundleId-targeted, with an `appium_capabilities.dart` entry and a session and
parser that mirror `xcuitest_backend.dart`, selected by
`native_backend_factory.dart` when the target is darwin. It keeps the canonical
per-node record schema, the pull-free perception invariant (`snapshot()` is a
watcher-fed read; `buildPerception()` stays synchronous), and the house rule of
Fakes not mocks with `fake_native_backend.dart` as the extension point. A
direct AX client is the FALLBACK, taken only if the alert-sheet spike — mac2
addressing another application's system alert sheet through the accessibility
tree with Accessibility granted to the Appium host — fails; that outcome is
recorded as an amendment to this entry, not assumed. Ruled by Nico in chat,
2026-09-18: "Appium mac2 for lenny".

### Consequences

* Good, because the iOS seam is reused end to end and no new host process or
  FFI surface enters the harness.
* Bad, because the driver depends on the Appium host holding macOS
  Accessibility permission, which is a one-time human grant on each Mac.
