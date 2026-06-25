# leonard_native spike (lenny-qxx.1) — RESULT: 🟢 GREEN / PASS

**Date:** 2026-06-20 · **Verdict:** feasibility PROVEN on the iOS 26 simulator.

## What was proven
On an **iOS 26 simulator** (iPhone 17 Pro), with **Appium 3.5.2 + appium-xcuitest-driver 11.12.2** under **Xcode 26.5**, a plain Appium/XCUITest session driving the **OS accessibility tree in NATIVE_APP context** can both **see and drive** the real **Auth0 Universal Login** web form launched from a Flutter app via `auth0_flutter`'s default `ASWebAuthenticationSession`.

- O1 reachability: the web inputs surface as native nodes — `XCUIElementTypeTextField name="Email address"`, `XCUIElementTypeSecureTextField name="Password"`. Right-page guard: `dev-y1gwg3ay5b5rl17n.us.auth0.com` present in the tree + screenshot shows the Auth0 page.
- Full drive: typed a per-run nonce email + password; **email readback == exact typed string** (acceptance #2), **password readback = masked non-empty ≠ plaintext** (acceptance #3). `verdict: PASS`.

## Risks retired (vs spec residual-risk list)
- **B1 (core reachability) — RETIRED locally.** XCUITest DOES see ASWebAuthenticationSession web inputs on the simulator. No pivot to WEBVIEW context / real device / Android needed for iOS.
- **B2 (iOS version) — handled.** Targeted iOS 26 / iPhone 17 Pro (no iOS 17 on this machine).
- **B3 (WDA on Xcode 26) — RETIRED.** WDA launched and drove fine; use Appium 3 + xcuitest 11.x.
- **FN3 (secure-field readback) — confirmed behavior.** Secure field returns masked bullets, not plaintext; acceptance asserts non-empty + ≠ plaintext (NOT length/equality).

## Confirmed known-working recipe (the m2 host should reproduce)
1. Appium 3 + xcuitest driver; caps `platformName=iOS`, `appium:automationName=XCUITest`, `appium:udid=<booted sim>`, `appium:app=<Runner.app>`, `appium:forceSimulatorSoftwareKeyboardPresence=true`.
2. Launch app → tap `//XCUIElementTypeButton[@name='Log in']`.
3. **Accept the ASWebAuthenticationSession consent via the W3C alert endpoint** `POST /session/{id}/alert/accept` — the consent ("… Wants to Use … to Sign In") is a SEPARATE SpringBoard process and is NOT in the app's `/source`, so an xpath find for "Continue" misses it. (Key finding.)
4. Fields are addressable by name: Email `//XCUIElementTypeTextField[@name='Email address']`, Password `//XCUIElementTypeSecureTextField[@name='Password']`.
5. Type via `POST /session/{id}/element/{eid}/value`; read back via `GET /session/{id}/element/{eid}/attribute/value`.
6. Per O11, stop before SIGN IN — proving the text landed is the de-risk goal.

## Artifacts (this dir)
- `o1_probe.py` — reachability probe (source-dump + analyze).
- `o1_drive.py` — full type+readback proof.
- `spike_source.xml` — GREEN a11y tree of the Auth0 page.
- `spike_screen.png` — Auth0 Universal Login rendered.
- `spike_drive_screen.png` — fields populated post-type.
- Target app: `~/lenny-spike/auth0_sample` (throwaway auth0_flutter sample, bundleId `com.nicospencer.lennyspike`, tenant `dev-y1gwg3ay5b5rl17n`).

## What's NOT proven (carry into m2 / later)
- Android (UiAutomator2 + Chrome Custom Tab) — no emulator on this machine; deferred (B4).
- Real-device iOS (vs simulator) — not needed for the proof, but note sim≠device.
- The production leonard_native shape (AppiumExtension + ExplorationHost + pull-free watcher) — that's m2, not the spike.
