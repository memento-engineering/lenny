## 0.2.2

- Fix: `UiAutomator2Backend.enterText` now types into Chrome web-content
  inputs. UiAutomator2 implements `POST /element/{id}/value` as
  `AccessibilityNodeInfo.performAction(ACTION_SET_TEXT)`, which Chrome's web
  `<input>` nodes refuse with `invalid element state` — so any consumer driving
  an OAuth/Auth0 login through a Chrome Custom Tab was blocked at the first
  text field. On that error `enterText` falls back to `click` +
  `mobile: type`, which injects key events. (`/keys` is NOT usable as the
  fallback: for arbitrary text it shares the same ACTION_SET_TEXT handler and
  fails identically.)
- The fallback verifies `attribute/focused` after its click and throws with the
  cause named rather than typing into the void. `mobile: type` reports HTTP 200
  even when the element cannot receive input, and for a MASKED field an empty
  readback is indistinguishable from a correct write, so an obstructed field
  would otherwise surface as a silently empty password. The known obstruction
  is Chrome's Touch-To-Fill sheet, which both refuses `ACTION_SET_TEXT` and
  swallows injected keystrokes — while it is up, NO write path succeeds, so the
  sheet must be dismissed before `enterText` can work at all.
- **Behaviour change, relevant if you have failure-triggered recovery:** an
  `enterText` that previously FAILED on a Chrome web input now succeeds, so
  recovery paths keyed on that failure will stop firing. Specifically, the
  click that focuses the field can raise Chrome's Touch-To-Fill "Use saved
  password?" sheet, and because the write now succeeds that sheet can survive
  into the next step and obscure a following submit tap. Dismiss it on its own
  signal rather than on an `enterText` error.
- `NativeException` gains an optional `code` carrying the W3C WebDriver error
  code (`invalid element state`, `no such element`, ...) when the failure came
  from a remote error body; `null` for transport and decode failures. Both
  backends populate it. `message` is unchanged and still carries the code as a
  prefix, so anything reading the message is unaffected.

## 0.2.0

- Breaking: the iOS `AppiumBackend` public API is renamed to
  `XcuiTestBackend`, and its `platform:` constructor parameter is removed.
- Migration: replace `AppiumBackend(..., platform: 'ios')` with
  `XcuiTestBackend(...)`.
- Breaking: VM-service methods now use the unified `ext.leonard.*` namespace
  supplied by `leonard_contract`.

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
