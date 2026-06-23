## 0.1.0 — initial native host

- Initial `leonard_native` package: `NativeExtension` (a stateful,
  self-watching `LeonardExtension`) projects the OS accessibility tree into a
  genesis_perception fragment and exposes `tap` / `enter_text` / `press` /
  `swipe` tools.
- The `NativeBackend` seam keeps all device I/O behind a synchronous
  `buildPerception()` (ADR-0006). `AppiumBackend` drives a local Appium server
  over W3C WebDriver against an iOS simulator (XCUITest); `FakeNativeBackend`
  is the shipped test impl.
- Standalone VM-service host runner at `bin/leonard_native_host.dart`.
