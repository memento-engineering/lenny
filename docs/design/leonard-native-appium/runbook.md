# Runbook — Appium native `enter_text` spike

Concrete, ordered, copy-pasteable setup + run steps. Read `spec.md` first —
several steps below have hard blockers (iOS reachability, version mismatch,
missing Android emulator) flagged inline as **[BLOCKER]**. Do the cheapest
falsifying experiment (Step 0) BEFORE building the full harness.

---

## Step 0 — RESOLVE THE PREMISE FIRST (do this before anything else)

The whole spike assumes the Auth0 web inputs surface as native XCUI nodes inside
`ASWebAuthenticationSession`. Appium issue #18805 says they may NOT (separate
protected SafariViewService process). Prove or disprove cheaply:

```bash
# 1. boot a sim (see Step 2 for an INSTALLED device — 'iPhone 15 Pro' is NOT available here)
xcrun simctl list devices available
xcrun simctl boot 'iPhone 17 Pro'   # an installed iOS 26 device; adjust to what `list` shows

# 2. build + install + run the auth0_flutter sample (Step 3), tap Sign In to open the Auth0 page

# 3. start Appium (Step 4), create a session (Step 6 caps), then dump page source:
SID=$(curl -s -X POST http://127.0.0.1:4723/session \
  -H 'content-type: application/json' \
  -d '{"capabilities":{"alwaysMatch":{"platformName":"iOS","appium:automationName":"XCUITest","appium:bundleId":"<SAMPLE_BUNDLE_ID>","appium:platformVersion":"26.5","appium:deviceName":"iPhone 17 Pro"},"firstMatch":[{}]}}' \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["value"]["sessionId"])')
curl -s http://127.0.0.1:4723/session/$SID/source -o /tmp/probe_source.xml
grep -E 'XCUIElementTypeTextField|XCUIElementTypeSecureTextField' /tmp/probe_source.xml

# 4. also confirm the screenshot is NOT black:
curl -s http://127.0.0.1:4723/session/$SID/screenshot \
  | python3 -c 'import sys,json,base64;open("/tmp/probe.png","wb").write(base64.b64decode(json.load(sys.stdin)["value"]))'
open /tmp/probe.png
```

DECISION GATE:
- If the grep finds `XCUIElementTypeTextField` + `SecureTextField` under the
  SafariViewService subtree -> the iOS leg is viable; proceed.
- If absent (only an opaque `XCUIElementTypeWebView`/`Other`) -> the iOS NATIVE_APP
  design CANNOT pass. Pivot: WEBVIEW context + `additionalWebviewBundleIds:['process-SafariViewService']`,
  OR a real device, OR Android-only, OR an app-controlled in-app WKWebView.
  Record the finding; do NOT run the full harness as designed.

---

## Step 1 — Install Appium + drivers

The repo pins Appium 1.22.3 for the a cloud device farm farm; **ignore that for the local
spike.** This machine is Xcode 26.5 / iOS 26, which needs the latest Appium +
drivers (Appium 2's bundled xcuitest may predate Xcode-26 support — see spec B3).

```bash
node --version && npm --version          # node/npm are present; appium is NOT installed
npm i -g appium                          # install latest (Appium 3.x)
appium driver install xcuitest
appium driver install uiautomator2
appium driver list --installed
appium driver doctor xcuitest            # MUST be green before any run
```

> If you must match the runbook's original Appium-2 wording:
> `npm i -g appium@2 ; appium driver install xcuitest ; appium driver install uiautomator2`
> — but verify the resolved xcuitest driver builds WDA under Xcode 26 first.

---

## Step 2 — Boot sim / device

### iOS [BLOCKER: no iOS 17 runtime, no 'iPhone 15 Pro' on this machine]

```bash
xcrun simctl list runtimes                       # confirm what's installed (here: iOS 26.x only)
xcrun simctl list devices available              # pick an INSTALLED device

# Option A (use what's here): retarget to iOS 26
xcrun simctl boot 'iPhone 17 Pro'

# Option B (match the original plan): install an iOS 17 runtime first (multi-GB)
# xcodebuild -downloadPlatform iOS
# then create + boot a 17.x 'iPhone 15 Pro' device

# Real-device path (only if forced): WDA must be signed by your own free Apple
# personal team via xcodebuild; not needed for the sim path.
```

### Android [BLOCKER: no emulator pkg, no system-image, no AVD on this machine]

```bash
adb devices                                       # currently empty
sdkmanager --list | grep -E 'emulator|system-images'   # currently absent
sdkmanager --install 'emulator' 'system-images;android-34;google_apis;arm64-v8a'
avdmanager create avd -n Pixel_7 -k 'system-images;android-34;google_apis;arm64-v8a' -d pixel_7
emulator -avd Pixel_7 &
adb wait-for-device && adb devices                # confirm the emulator is seen
```

> If you scope the spike to iOS-only (recommended given the iOS reachability is
> the open question), skip the Android setup and defer it.

---

## Step 3 — Build + install the TARGET (throwaway auth0_flutter sample)

TARGET = the throwaway `auth0_flutter` sample, NOT the in-house app (the in-house app is
SSO-gated and unbuildable here).

1. Provision a FREE Auth0 dev tenant: one **Native** application + one test user +
   Universal Login enabled. Confirm Attack Protection (Bot Detection /
   Brute-force) is OFF and the user has no MFA policy. Note `domain` + `clientId`.
2. Author a ~50-line Flutter app: one "Log in" button calling
   `Auth0(domain, clientId).webAuthentication(scheme: customScheme).login()`.
   Decide `prefersEphemeralWebBrowserSession` (recommend **false** so a consent
   sheet appears, matching the in-house app).
3. Add the callback wiring: iOS `CFBundleURLSchemes` =, Android
   `appAuthRedirectScheme` = your custom scheme.
4. Build + install to the booted sim/emulator and note the ids:

```bash
flutter pub get
flutter run                                       # installs to the booted sim/emulator
# iOS: note CFBundleIdentifier (the appium:bundleId)
# Android: note applicationId (appium:appPackage) and the launch activity
#   (appium:appActivity) from the built AndroidManifest — do NOT hardcode proprietary's.
```

---

## Step 4 — Start Appium

```bash
appium --address 127.0.0.1 --port 4723
# wait for: "Appium REST http interface listener started on 127.0.0.1:4723"
# or probe in another shell:
until curl -fs http://127.0.0.1:4723/status >/dev/null 2>&1; do sleep 1; done; echo "appium up"
```

---

## Step 5 — Scaffold the spike

```bash
mkdir -p spikes/spike_appium/bin
# pubspec.yaml: publish_to: none, environment.sdk ^3.11.0, dependencies: http ^1.2.0
# bin/spike.dart: the backend_skeleton.dart from this spike (apply the spec hardening fixes)
# NOTES.md: re-run command + verdict
dart pub get
```

`spikes/spike_appium/pubspec.yaml`:

```yaml
name: spike_appium
publish_to: none
environment:
  sdk: ^3.11.0
dependencies:
  http: ^1.2.0
```

> Before running: apply the spec's hardening mutations to `bin/spike.dart` —
> `_unwrap` honors HTTP status + non-JSON bodies (B5); `readValue` branches
> iOS `value` / Android `text` (FN4); drop `length >= pw.length` (FN3); add a
> right-page `/source` machine gate (FP1/FP2); guard + fix the Android back route
> (B6); per-run nonce email (FP3); required bundleId/appPackage args (B8).

---

## Step 6 — Run iOS first

IMPORTANT: edit the caps `bundleId`/`appPackage` in `main()` to the sample's ids
before running (the skeleton ships reference placeholders). Use an INSTALLED
device + OS (see Step 2 — `iPhone 15 Pro` / iOS 17 are NOT available here).

```bash
# Original plan (will FAIL New Session on this machine — version mismatch):
# dart run spikes/spike_appium/bin/spike.dart --platform ios --os 17 \
#   --email test@example.com --password 'P@ssw0rd!' --device 'iPhone 15 Pro'

# Runnable here (iOS 26 + installed device + per-run nonce email):
dart run spikes/spike_appium/bin/spike.dart \
  --platform ios --os 26 \
  --device 'iPhone 17 Pro' \
  --email "spike+$(date +%s)@example.com" \
  --password 'P@ssw0rd!'
```

---

## Step 7 — Assert

PASS requires:
- Exit code `0`.
- stdout JSON shows `emailOk:true`, `passwordMasked:true`, `passwordLanded:true`.
- `spike_screen.png` visibly shows the Auth0 Universal Login page with the typed
  email in the box (NOT the Flutter launch screen).

```bash
dart run spikes/spike_appium/bin/spike.dart --platform ios --os 26 \
  --device 'iPhone 17 Pro' --email "spike+$(date +%s)@example.com" --password 'P@ssw0rd!'
echo "exit=$?"
open spike_screen.png
grep -E 'auth0|SIGN IN|Email' spike_source.xml   # right-page machine check
```

Then repeat with `--platform android --device Pixel_7` (only after Step 2 Android
setup completes).

---

## Step 8 — Tamper-test (prove non-vacuity)

```bash
# email tamper: type a wrong value -> expect exit 1
dart run spikes/spike_appium/bin/spike.dart --platform ios --os 26 \
  --device 'iPhone 17 Pro' --email "wrong@nope.com" --password 'P@ssw0rd!'
echo "expect exit=1, got exit=$?"

# password tamper (extend the original plan): type nothing into password ->
# expect passwordLanded:false and exit 1, proving the masked assertion is not vacuous.
```

Record the verdict + the exact re-run command in `spikes/spike_appium/NOTES.md`
and append a row to `spikes/RESULTS.md`. Note the Appium-version divergence
(local 3.x vs repo 1.22.3) in NOTES.md.
