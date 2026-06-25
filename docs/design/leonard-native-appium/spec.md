# Spike Spec — Appium-backed native `enter_text` de-risk

## Objective

Prove that a Leonard-shaped driver can **find a real Auth0 login field, type into
it, and read the typed characters back** over an Appium W3C-WebDriver session —
i.e. de-risk a future `native.enter_text` capability against the *hardest* real
surface (a hosted Auth0 Universal Login form launched from a Flutter app).

This is a throwaway de-risk, not production code. It deliberately does **not**
adopt the full `leonard_tmux` shape (no `genesis_perception` projection, no poll
`ObservationSource`, no `ExplorationHost`). It borrows only the de-risk-sized
shape: an immutable cached source snapshot refreshed by an explicit pull, plus
refresh-after-act. A single driver thread calls `observe()` explicitly at each
step — a poll loop buys nothing for a one-shot script and only adds ADR-0006
ceremony a throwaway does not need.

**Upgrade path (NOT this spike):** wrap `AppiumBackend` as an `AppiumExtension`
mirroring `TmuxExtension` — cached `AppiumObservation` + poll watcher + pull-free
`buildPerception()` — hosted via `ExplorationHost` so `leonard_drive`
observe/invoke/screenshot drive it with no new driver code.

## Chosen TARGET

**TARGET = a throwaway `auth0_flutter` sample app against a free Auth0 dev
tenant.** A ~50-line Flutter app with one "Log in" button calling
`Auth0(domain, clientId).webAuthentication(scheme: customScheme).login()`.

### Rationale

- **The in-house app is unbuildable here.** The proprietary in-house app is
  SSO-gated and cannot be built on this machine; using it as the TARGET is a
  non-starter.
- **It exercises the real hard surface.** The login leg runs inside
  `ASWebAuthenticationSession` (iOS) / Chrome Custom Tab (Android) — a hosted web
  page, not a Flutter widget. That is *exactly* the surface
  `native.enter_text` must conquer, and the one the reference login-recipe
  selectors were written against.
- **Custom scheme sidesteps signing.** `webAuthentication(scheme: customScheme)`
  makes the callback a custom URL scheme, avoiding the Universal-Link /
  associated-domain signing problem that would otherwise force a real device.
  (Caveat — see residual risks: custom scheme fixes the *callback*, not form
  *inspectability*.)
- **No proprietary access needed.** A free Auth0 dev tenant (one Native app + one
  test user + Universal Login) reproduces the flow with zero proprietary
  dependencies.

### Selectors / recipe provenance

Selectors, sleeps, and guards in the harness are copied **verbatim** from a
reference login recipe's `stepSequence` (its context-switch step; its consent +
keyboard branches). They are **unproven against a live
`ASWebAuthenticationSession` DOM on a simulator** — the reference recipe ran on a
cloud real-device farm (Appium 1.22.3). De-branding the app/host-specific strings
is a pre-run open item (below).

## Acceptance criteria

PASS requires **ALL** of:

1. **Reached field-readback with NO `AppiumError`.** Every `find(required:true)`
   returned a handle, proving the real Auth0 email + password fields existed in
   the NATIVE_APP tree.
2. **`readValue(emailField) == the exact email typed.** The
   `XCUIElementTypeTextField` / `android.widget.EditText` echoes its value
   attribute; exact-equality readback proves the characters landed in **the
   Auth0 email field specifically**.
3. **Password `SecureTextField` readback is NON-EMPTY and != plaintext.** A
   secure field masks (bullets/length); non-empty proves keystrokes landed,
   masking proves it is the real secure field.

### Observable proof

- stdout emits **exactly one** JSON line:
  `{event:spike_result, emailField, emailOk, passwordMasked, passwordLanded}`.
- The process exits `0` **only** when `emailOk && passwordMasked && passwordLanded`.
- `spike_source.xml` + `spike_screen.png` are written at assert time as
  human-auditable proof. The screenshot must visually show the Auth0 Universal
  Login page (the tenant's Auth0 branding) with the typed email in the box —
  **NOT** the app's Flutter launch screen.

### False-positive guards (baked into acceptance)

- (a) Read each field's **own** `attribute/value`, never a substring match
  against `/source` — a source match could hit a placeholder/label.
- (b) The email assert is **exact-equality** to the typed string, so a stale or
  empty field fails.
- (c) Every field find is `required:true` — a missing field hard-fails, never
  silently skipped.
- (d) The password is asserted **masked-and-nonempty**, not equals-plaintext —
  equals-plaintext would indicate we typed into the WRONG (non-secure) field.
- (e) `spike_source.xml` + `spike_screen.png` captured at assert time as
  human-auditable proof.

### FAIL conditions

Any `AppiumError` (no session, element not found, W3C error envelope);
`emailVal != email`; password field empty (no keystrokes) or password field ==
plaintext (wrong/non-secure field); source/screenshot show the Flutter app
instead of the hosted browser (context switch or page launch failed).

### Vacuity check (mandatory)

Tamper-test once (type a deliberately wrong string) and confirm the suite flips
to exit `1`. This proves the acceptance check is not vacuous. **Extend the
tamper-test to the password side too** (type nothing into password; confirm it
flips red) — otherwise the masked-field assertion is vacuous.

## Implementation plan

1. Create `spikes/spike_appium/` mirroring the existing spike convention
   (`publish_to: none`): `pubspec.yaml` depending only on `http ^1.2.0`,
   `bin/spike.dart`, `NOTES.md`. No path dep on leonard packages is needed for
   the de-risk.
2. Implement `AppiumBackend` per the skeleton: transport `_post`/`_get` with W3C
   envelope unwrap + typed `AppiumError`; `connect`/`quit`;
   `context`/`find`/`tap`/`type`/`readValue`/`observe`/`back`.
3. Add the recipe layer: platform-branched selectors + sleeps +
   `dismissKeyboard` (iOS Done with `OS_VERSION '26'` skip, Android back) + the
   iOS consent-popup branch, all copied verbatim from the LOGIN RECIPE
   `stepSequence`.
4. Wire `main()`: parse args, build minimal repo-grounded caps, run context →
   launch → consent → email → password, then the field-readback acceptance
   asserts; emit the `spike_result` JSON line; write `spike_source.xml` +
   `spike_screen.png`; exit 0/1.
5. Author the throwaway `auth0_flutter` target app (separate tiny Flutter
   project, `auth0_flutter ^2.0.0`) against a free Auth0 dev tenant; choose its
   bundleId/appPackage and swap them into the caps.
6. Run end-to-end on an iOS simulator first (XCUITest), then an Android emulator
   (UiAutomator2); tamper-test the acceptance assert.
7. Write `NOTES.md` (re-run command + verdict) and append a row to
   `spikes/RESULTS.md`. Optional follow-up bead: promote `AppiumBackend` into an
   `AppiumExtension` + `ExplorationHost` (the `leonard_tmux`-shaped production
   path) so `leonard_drive` can drive it.

---

## Consolidated residual-risk list

Merged from three skeptic lenses (ios-reach, creds-build, backend-correctness),
grouped by kind, each with its mitigation. **Severity** in brackets.

### BLOCKERS (will stop a run cold; must be resolved first)

- **B1 [HIGH] — Core reachability premise may be false (iOS).**
  `ASWebAuthenticationSession` runs in a separate, privacy-protected system
  process (SafariViewService). Appium's XCUITest driver cannot inspect it
  (appium#18805, WDA#708, appium#13776 — all ThirdParty/unresolved). The entire
  spike runs in NATIVE_APP and finds fields by `//*[@type='XCUIElementTypeTextField']`
  / `SecureTextField`, assuming the Auth0 web inputs surface as native XCUI
  nodes. If they do **not**, every `find(required:true)` throws and the spike
  exits 1 — a FALSE-NEGATIVE indistinguishable from "native.enter_text doesn't
  work." The reference recipe only ever READ the consent sheet (OS chrome) and
  the URL bar; there is **no evidence** it typed into the in-page web inputs via
  NATIVE_APP xpath.
  *Mitigation:* RESOLVE FIRST with the cheapest falsifying experiment (see Open
  Items O1). Dump `GET /session/{id}/source` with the Auth0 page open and confirm
  `XCUIElementTypeTextField` + `SecureTextField` appear under the
  SafariViewService subtree. If absent: switch to WEBVIEW context +
  `additionalWebviewBundleIds:['process-SafariViewService']` (documented but
  flaky), OR scope to a real device and report "sim cannot reach this surface" as
  the finding, OR pivot to Android (Chrome Custom Tab + `android.widget.EditText`
  is at least addressable in NATIVE_APP), OR have the app use a self-controlled
  in-app WKWebView (WEBVIEW works, but diverges from the in-house app's real flow).

- **B2 [HIGH] — iOS version / device mismatch.** This machine has ONLY iOS
  26.2/26.4/26.5 runtimes + Xcode 26.5; there is NO iOS 17 runtime and no
  "iPhone 15 Pro" device available (available: iPhone 16/16e/17/17 Pro/Air on
  iOS 26). The runbook's `--os 17 --device 'iPhone 15 Pro'` and the default caps
  (`platformVersion '17'`, `deviceName 'iPhone 15 Pro'`) will fail New Session
  before any field is touched.
  *Mitigation:* Either install an iOS 17 runtime
  (`xcodebuild -downloadPlatform iOS`) OR retarget to iOS 26
  (`deviceName 'iPhone 17 Pro'`, `platformVersion '26.x'`, pass `--os 26`). On
  iOS 26 the `OS_VERSION contains '26'` Done-key-skip branch fires — UNTESTED, a
  verbatim guess from the recipe. Pin the target OS in caps + runbook before any
  run.

- **B3 [HIGH] — WDA / XCUITest may not launch on Xcode 26 / iOS 26.** Active open
  issues (appium#21643 "WebDriverAgent fails to launch on iOS 26", appium#21347).
  Forced onto Xcode 26.5 + iOS 26 sims, WDA may never attach; session create or
  first command times out — pure infra, exits 1 with an `AppiumError`
  indistinguishable from a real hypothesis failure.
  *Mitigation:* Use **Appium 3 (latest)** + latest xcuitest/uiautomator2 drivers
  — NOT the runbook's `appium@2` pin (whose xcuitest driver may predate Xcode-26
  support; the repo's 1.22.3 pin is irrelevant for a local sim spike). Run
  `appium driver doctor xcuitest` green. Smoke-test WDA against the sample app's
  **own** native "Sign In" button (clean `/source` dump) BEFORE the Auth0 leg, so
  infra failure is attributed separately from field reachability.

- **B4 [HIGH] — Android leg cannot run at all.** No `emulator` package, no
  system-image, no AVD; `adb devices` shows nothing. Runbook steps 2 and 7 are
  not executable.
  *Mitigation:* `sdkmanager --install 'emulator' 'system-images;android-34;google_apis;arm64-v8a'`
  then `avdmanager create avd` (budget download + first-boot time). OR scope the
  spike to iOS-only and explicitly defer Android. NB: once installed, Android may
  be the MORE viable platform (Chrome Custom Tab + `android.widget.EditText` is
  addressable in NATIVE_APP, unlike iOS B1).

- **B5 [HIGH/BLOCKER] — `_unwrap` bypasses the "load-bearing" W3C guard.**
  `_post`/`_get` ignore HTTP status and unconditionally `jsonDecode`. The error
  envelope is only honored for valid-JSON bodies. A 404/500/HTML-error-page/empty
  body throws `FormatException`, not `AppiumError`. `find()`'s retry catches only
  `on AppiumError`, so a `FormatException` escapes and aborts; `connect`/`context`/
  `type` have no catch at all. The primary false-positive guard is bypassed by
  every non-JSON failure.
  *Mitigation:* In `_unwrap`, check `statusCode` first; on non-2xx OR
  `value.error`, throw a typed `AppiumError` including status + raw body. Wrap
  `jsonDecode` in try/catch rethrowing as `AppiumError('non-JSON response: ...')`.
  Then `find()`'s retry actually covers transient 404s and the guard holds.

- **B6 [MED/BLOCKER] — Android keyboard-dismiss route may 404.** `dismissKeyboard`
  uses awaited, unguarded `POST /session/{id}/back`. On Appium 2/3 UiAutomator2
  the canonical back is `POST /session/:id/appium/device/press_keycode` (or
  `mobile: pressKey`); the bare `/back` route may 404 → `AppiumError`/
  `FormatException` aborts mid-login.
  *Mitigation:* Use the UIA2-supported back path AND wrap `dismissKeyboard` in a
  non-fatal try/catch (keyboard dismissal is cosmetic to the proof). Verify the
  route against the live driver first.

- **B7 [MED/BLOCKER] — Appium not installed.** Only node/npm present; `appium`
  is absent (`fvm` also absent, though the sample doesn't need it).
  *Mitigation:* Install Appium (3, latest) + drivers; `appium driver doctor
  xcuitest` green before the live run.

- **B8 [MED/BLOCKER] — placeholder bundleId/appPackage ship in caps.**
  The skeleton carries `com.example.inhouse` / `com.example.app` /
  `...MainActivity` as comment-only placeholders. An un-swapped run targets an
  uninstalled app and fails at session create (or attaches to nothing).
  *Mitigation:* Make bundleId/appPackage/appActivity **required CLI args with no
  hardcoded defaults**, so an un-swapped run hard-fails loudly. Derive appActivity
  from `flutter run` / the sample manifest; do not hardcode.

### FALSE-NEGATIVES (real success misreported as failure)

- **FN1 [MED] — iOS simulator keyboard swallows sendKeys.** `type()` →
  `element/{eid}/value` commonly throws "Keyboard is not present" or no-ops when
  "Connect Hardware Keyboard" is on (appium#10418, xcuitest-driver#2551). The
  email exact-equality readback then fails for a keyboard-config reason, not
  because native.enter_text is incapable.
  *Mitigation:* Set caps `forceSimulatorSoftwareKeyboardPresence:true` (or
  `connectHardwareKeyboard:false`); ensure Hardware > Keyboard > Connect Hardware
  Keyboard is OFF. Keep `tap(field)` before `type`. Add a retry-once on empty
  readback before declaring failure.

- **FN2 [MED] — Consent selector is app-specific.** The iOS consent title
  `//*[@value='“<App Name>” Wants to Use “<tenant-host>” to Sign In']` will read
  e.g. `'"Spike" Wants to Use "<tenant>.us.auth0.com" to Sign In'` for the
  sample. The branch is guarded/non-fatal so it won't throw — but if Continue is
  never tapped, the Auth0 page never loads, field finds time out, and the spike
  false-fails. (Conversely, `prefersEphemeralWebBrowserSession:true` → no consent
  sheet, making the 4s sleep + probe dead weight but harmless.)
  *Mitigation:* Match Continue by the stable `//*[@name='Continue']` only (or
  parameterize the title with the sample's app name + tenant host). Decide
  explicitly whether the sample uses ephemeral session (recommend **false**, so
  the flow matches the in-house app). Capture `/source` right after Sign In to confirm
  whether a consent sheet actually appears.

- **FN3 [MED] — Secure-field readback may report empty/`'0'`/fixed-bullets on a
  web SecureTextField.** Web inputs surfaced through SafariViewService often
  report `''` for value via the native a11y bridge. `passLanded`
  (`length >= pw.length`) then fails on a genuine success.
  *Mitigation:* Probe the live secure field's `attribute/value` BEFORE locking
  the assertion. **Drop `length >= pw.length`** — keep only
  `(passVal.isNotEmpty && passVal != pw)`; to prove N keystrokes landed, type a
  known nonce and accept any non-empty masked readback (bullet count != char
  count). Fall back to email echo + screenshot if the secure field reports ''.

- **FN4 [HIGH] — Android `readValue` uses the wrong attribute.** On UiAutomator2
  the EditText `value` attribute is typically null/unsupported; typed content is
  exposed via `text`. As written, `attribute/value` returns empty on Android and
  `emailOk` fails even when keystrokes landed. The skeleton does not branch.
  *Mitigation:* Branch `readValue` by platform — iOS `attribute/value`, Android
  `attribute/text` — verified against a live `/source` dump of the field first.
  Do not promote the Android verdict until confirmed.

- **FN5 [LOW] — `find()` retries on every `AppiumError`.** A malformed xpath or
  dead session becomes a slow 10s "not found" instead of an immediate diagnostic
  failure — muddies the verdict (not a false-positive).
  *Mitigation:* Inspect the error code: retry only on `no such element` /
  `stale element`; rethrow immediately on `invalid selector` / `invalid session
  id` / `no such window`.

### FALSE-POSITIVES (failure or wrong target misreported as success)

- **FP1 [HIGH] — Email field has no anti-wrong-field guard.**
  `//*[@type='XCUIElementTypeTextField']` can match the browser URL bar or a
  search box. If `find` picks the wrong TextField, type+readback still returns
  exact-equality (we typed there, read it back) and `emailOk` passes — text
  landed, but NOT in the Auth0 email field. The tamper-test does not catch this
  (reads back from the same wrong element).
  *Mitigation:* Corroborate context as a HARD exit-1 condition: assert the URL
  element (recipe url_bar / `com.android.chrome:id/url_bar`) contains the
  Auth0/tenant domain, OR assert the email field's sibling label == 'Email', OR
  machine-check the captured `/source` XML for Auth0 form markers. At least one
  must be a hard gate, not human-only screenshot review.

- **FP2 [MED] — `/source` + screenshot "visual proof" is prose-only, never
  machine-enforced.** Exit can be 0 with `spike_screen.png` showing the Flutter
  launch screen if the context switch silently degraded and a stray TextField got
  the text. The acceptance is only as strong as a human opening the PNG.
  *Mitigation:* Add a machine gate on `snap.source`: assert the XML contains an
  Auth0-page marker (the SIGN IN web button, the tenant/auth0 domain string, or
  the SecureTextField sibling structure); fail exit-1 if absent. Keep the PNG as
  human audit, not the sole right-page guard.

- **FP3 [MED] — `noReset:true` + fixed `test@example.com` lets a stale/autofilled
  value pass falsely.** With `noReset` the prior run's autofill/cookies/typed
  value persist; if `type()` silently no-ops but the field already held a matching
  value, `emailOk` passes.
  *Mitigation:* Type a per-run unique nonce email
  (`spike+<epoch>@example.com`). Prefer a fresh simulator or `fullReset:true` over
  `noReset:true` for the proof run.

- **FP4 [LOW] — Screenshot of the protected browser surface may be black.**
  SafariViewService is privacy-protected; XCUITest screenshots can return black
  or app-only, undercutting the human-auditable proof.
  *Mitigation:* Verify a real screenshot renders the web page during the manual
  probe (O1). If black, drop the "screenshot must show Auth0 page" clause and
  rely on `/source` + field readback, noting the limitation.

- **FP5 [MED] — Custom scheme is conflated with form inspectability.** The plan
  treats "custom scheme avoids signing" (true) as "therefore the form is
  reachable" (false). Custom scheme fixes only the callback; the login UI is
  still in `ASWebAuthenticationSession`, so it does NOT fix B1.
  *Mitigation:* Keep custom scheme for the callback. If iOS is kept, evaluate
  auth0_flutter's option to use an in-app web view / SFSafariViewController vs
  ASWebAuthenticationSession and pick whichever is inspectable — and document
  that this DIVERGES from the in-house app's real ephemeral-session flow (weaker
  proof than claimed).

### Low-risk / sound-as-written (noted, no action gating the run)

- Simulator sidesteps app code-signing; WDA signing only matters on a real device
  — staying on the sim avoids it.
- A fresh free Auth0 dev tenant has no MFA and no bot-detection by default, and
  the plan stops before tapping SIGN IN, so submission-side protections never
  engage. Confirm Attack Protection (Bot Detection / Brute-force) is OFF and the
  test user has no MFA policy.

---

## Open items — MUST be resolved before a live run

- **O1 — RESOLVE THE CORE REACHABILITY QUESTION FIRST (cheapest falsifying
  experiment).** Boot a sim, launch the auth0_flutter sample, open the
  ASWebAuthenticationSession Auth0 page, dump `GET /session/{id}/source`. Confirm
  `XCUIElementTypeTextField` + `XCUIElementTypeSecureTextField` actually appear
  under the SafariViewService subtree in NATIVE_APP context. If they do NOT, the
  spike as designed CANNOT pass on this surface — redesign (WEBVIEW context +
  `additionalWebviewBundleIds:['process-SafariViewService']`) or scope to a real
  device or pivot to Android. Do not run the full harness until answered. While
  here, also verify the screenshot renders the web page (not black) — addresses
  FP4.

- **O2 — Provision a free Auth0 dev tenant.** domain + clientId + custom callback
  scheme + one test user (no proprietary access needed). Confirm Attack Protection
  OFF and no MFA on the test user. Decide
  `prefersEphemeralWebBrowserSession` (recommend **false** so there IS a consent
  sheet matching the in-house app) — affects FN2.

- **O3 — Author the throwaway `auth0_flutter` sample (~50 lines) and choose its
  bundleId/appPackage.** The skeleton ships placeholder
  `bundleId`/`appPackage` (`com.example.inhouse` / `com.example.app`) that
  MUST be swapped (make them required args — B8). Derive `appActivity` from the
  built manifest.

- **O4 — Pin a runnable iOS target.** This machine has only iOS 26.x sims + no
  "iPhone 15 Pro". Either install an iOS 17 runtime OR retarget caps + runbook to
  an installed iOS 26 device (e.g. `iPhone 17 Pro`, `platformVersion 26.x`) and
  pass `--os 26` so the Done-key-skip branch engages (B2).

- **O5 — Make Android runnable or explicitly drop it.** No emulator package, no
  system-image, no AVD, no connected device. Install + create an AVD, or scope to
  iOS-only (B4).

- **O6 — Pin a Xcode-26-compatible Appium + driver matrix.** Use Appium 3 (latest)
  + latest xcuitest/uiautomator2 drivers; `appium driver doctor xcuitest` green;
  smoke-test WDA against the sample's own native button before the Auth0 leg (B3).

- **O7 — Confirm the element-value attribute per driver.** iOS XCUITest exposes
  `value`; Android UiAutomator2 likely needs `attribute/text`. Verify against a
  live source dump and branch `readValue()` accordingly (FN5/FN4).

- **O8 — Configure the sim keyboard for sendKeys.**
  `forceSimulatorSoftwareKeyboardPresence:true` / `connectHardwareKeyboard:false`
  and disconnect the hardware keyboard, to avoid "Keyboard is not present"
  swallowing keystrokes (FN1).

- **O9 — De-brand the consent handler.** Match Continue by
  `//*[@name='Continue']` only (or parameterize title with the sample's app name
  + actual tenant host), not the verbatim '<App Name>' / '<tenant-host>' string
  (FN2).

- **O10 — Probe the secure-field value behavior on the live web input before
  locking the masked-and-nonempty assertion.** Have a fallback (email echo +
  screenshot) if the web SecureTextField reports empty value (FN3).

- **O11 — Decide whether to STOP before tapping SIGN IN (recommended for the
  de-risk).** Proving the text landed is the whole goal; actually authenticating
  adds Auth0-tenant flakiness and is not needed for the native.enter_text proof.

- **O12 — Note the Appium version divergence in NOTES.md.** The local spike uses
  Appium 3 (latest) + xcuitest/uiautomator2; the reference recipe's cloud-farm
  path pins 1.22.3 — keyboard/secure-field behavior may differ.

### Hardening required before run (folded into the skeleton, summary)

Per the backend-correctness lens, before any run the throwaway code must:
fix `_unwrap` to honor HTTP status + non-JSON bodies (B5); branch `readValue` by
platform (FN4); drop `length >= pw.length`, keep non-empty + != plaintext (FN3);
add a right-field/right-page machine assertion as a hard exit-1 (FP1/FP2); fix +
guard the Android keyboard-dismiss route (B6); use a per-run nonce email +
fresh-sim/`fullReset` (FP3); and make bundleId/appPackage/appActivity required
args (B8). The shipped skeleton (`backend_skeleton.dart`) is the **un-hardened
de-risk shape** as designed; these fixes are the documented mutations to apply
before trusting any verdict.
