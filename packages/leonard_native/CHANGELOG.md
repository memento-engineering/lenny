## 0.1.2

- Android support: `UiAutomator2Backend` drives a native Android app over a
  local Appium server running the UiAutomator2 driver — the additive sibling of
  the iOS `AppiumBackend`. It shares the generic W3C transport (session, element
  find, the 4-tier resolve chain, pointer-action tap/swipe) and keeps every
  Android divergence inside the impl: a `<hierarchy>` `/source` parser,
  content-desc as the tier-1 identifier, resource-id-or-positional xpath
  synthesis, attribute/password-derived masking with attribute/text readback,
  and a press vocabulary where `back` is recognized and the iOS-only alert keys
  throw.
- New `backendForPlatform(...)` — the one place that maps a platform string to a
  `NativeBackend`, so the wiring is testable without a device. An unrecognized
  platform throws rather than silently falling back to iOS (which would parse an
  Android tree with the XCUITest parser and observe nothing).
- `bin/leonard_native_host.dart` selects through `backendForPlatform`, so
  `--platform android` now works; an unsupported platform is an exit-64 usage
  error rather than an uncaught throw.

## 0.1.1

- The per-node record now surfaces the OS accessibility identifier under the
  canonical `identifier` key — the same stable, locale-proof addressing key as
  Flutter's `Semantics(identifier:)` — for cross-host record parity with the
  Flutter semantics fragment. Previously `a11yId` was selector-internal and
  never wired to the observation.

## 0.1.0 — initial native host

- Initial `leonard_native` package: `NativeExtension` (a stateful,
  self-watching `LeonardExtension`) projects the OS accessibility tree into a
  genesis_perception fragment and exposes `tap` / `enter_text` / `press` /
  `swipe` tools.
- The `NativeBackend` seam keeps all device I/O behind a synchronous
  `buildPerception()`. `AppiumBackend` drives a local Appium server
  over W3C WebDriver against an iOS simulator (XCUITest); `FakeNativeBackend`
  is the shipped test impl.
- Standalone VM-service host runner at `bin/leonard_native_host.dart`.
