# lenny-qxx.5 — leonard_native m5: Auth0 e2e (Build Spec)

**Base branch:** `feat/leonard-native` (the epic + m2/m3/m4 stack here — do **NOT** land m5 to `main`). m5 is the **LAST functional milestone** of `lenny-qxx`; m6 (new backends) is deferred.
**Package under change:** `packages/leonard_cli` (one new hardware-gated dogfood e2e + the `test:e2e:auth0` melos entry) + `packages/leonard_native` (ONE minimal additive `press` key behind the `NativeBackend` seam — see §4). `leonard_agent` is **untouched** (m3 already gave it `MultiHostSession`/merge/route).
**Status of dependencies (both LANDED + live-proven on `feat/leonard-native`):**
- **m3** (`lenny-qxx.3`) — `MultiHostSession` (attach N hosts, merge fragments side-by-side, route `ns.tool` to the owning host) + the `leonard_drive drive-dual <tools|observe|invoke>` subcommand. The e2e precedent is `packages/leonard_cli/test/drive_dual_e2e_test.dart`.
- **m4** (`lenny-qxx.4`) — `leonard_drive up` native dual path (`DualLaunchHandle{flutterWsUri, nativeEndpoint, deviceId}`, one `vm_service_ready` line, two-line flutter-first `--uri-file`). The e2e precedent is `packages/leonard_cli/test/launch_dual_e2e_test.dart`.

The **full Auth0 round-trip is already de-risked LIVE** — `~/lenny-spike/o2_login.py` drove it GREEN (tap Log in → accept consent → clear+type email+password → tap Continue → dismiss the Save-Password alert → poll `/source` until `logged in` appears). m5 does **not re-derive** that recipe; it **lifts the same calls onto the lenny harness** (`leonard_drive drive-dual invoke --tool native.*`/`core.*`) and proves **the product**, not raw Appium, can do it end to end — including the **resume-on-Flutter** signal that the spike confirmed but the harness has never asserted through the merged observation.

---

## 1. Goal & Scope

m5 is **only the dogfood e2e** (plus the one `press` key the round-trip needs). It adds a single hardware-gated test that drives the full loop **through the lenny harness**:

1. **Tap "Log in" on the Flutter channel** → the app opens Auth0 (iOS `ASWebAuthenticationSession`) → the Flutter `core` fragment goes quiet.
2. **The `native` fragment lights up** with the Auth0 web form (email / password / Continue) + the SpringBoard consent sheet.
3. **Drive the Auth0 form via `native.*`**: accept consent → `enter_text` email (clear-before-type) → `enter_text` password (clear-before-type, reads back masked) → tap Continue → handle the authorize screen + the iOS Save-Password interstitial.
4. **Auth0 redirects to the `com.nicospencer.lennyspike://…` callback** → control returns to Flutter → the `core` fragment **relights** with the status `Text` showing `logged in: <email>` → **assert resume-on-Flutter** through the merged observation.

The invariant that makes both channels watch one screen is **m4's shared device identity** (one `udid` → both `flutter run -d <udid>` and the native host `--udid`); m3 merges what each host reports. m5 trusts both and drives the sequence.

The Auth0 web auth is an **`ASWebAuthenticationSession` SHEET presented ON TOP of the still-alive Flutter app process** — the app never terminates during the round-trip, and the Flutter channel (`flutter_ws_uri`) stays live throughout. That is *why* the resume-on-Flutter signal is observable: the same Flutter process that opened the sheet relights with the authenticated status when control returns. See §3.0 for the hard correctness consequence (no terminate, ever).

### 1.1 The one genuinely-new thing m5 proves

m3's e2e **STOPPED before SIGN IN**; m4's STOPPED before SIGN IN. m5 is the milestone that **crosses sign-in and asserts the round-trip closes**: that after the OS-level Auth0 drive completes, the **deeplink callback returns control to Flutter** and the **Flutter `core` fragment relights** with the authenticated status — observed through the *same* merged observation m3 built, not via raw Appium `/source`. This is the epic's headline claim ("real Auth0 web login, perceive+drive across the OS/Flutter boundary, resume on Flutter") made true end to end on the product.

The first half of that claim — **Step 1's `core.tap`** — is also the milestone's headline **core→native handoff**, and it exposes a deliberate **selector asymmetry** between the two channels (§2). The Flutter `core.tap` is `node_id`-only; the native `native.tap` accepts `id|label|xpath|rect`. m5 is the first test to drive *across* that asymmetry: resolve the Flutter button's integer node id from the merged observation, tap it on `core`, then drive the form on `native`.

### Explicitly out of scope (do NOT build these here)

- **Android.** The native host is `--platform ios` only (mirrors m4 / `AppiumBackend` / m3). No Android path.
- **m6 — new backends** (`lenny-qxx.6`): `PatrolBackend` / `XcuitestBackend` / `PlatformChannelBackend`. m5 drives through `AppiumBackend` (the only impl) via the held native host; it adds no backend.
- **The autonomous-LLM-loop variant.** m5 drives the round-trip with the **external-brain `drive-dual invoke` pattern** (deterministic, scripted, no model) — the same stateless front-door m3's e2e used. Wiring lenny's OWN autonomous loop (`leonard_cli --launch` + a model that *chooses* `native.tap` vs `core.tap` by perception) to authenticate against Auth0 is **deferred** (it needs a stable provider + a reward signal and adds model nondeterminism to a hardware-gated test — wrong tier). The merged observation m5 asserts is exactly what that loop would perceive, so the autonomous variant is unblocked by m5 but not built here.
- **Any change to `MultiHostSession` / merge / route / the loop.** m3 owns those and is byte-for-byte unchanged. m5 only *consumes* `drive-dual`.
- **Any change to the launch lifecycle.** m4 owns `up`/`down`/`DualLaunchHandle`. m5 only *consumes* the `up`-held dual session.
- **A general `await_for_text` / poll-until primitive.** The adaptive dismiss + resume poll is orchestrated **by the test** (it `Process.run`s `drive-dual` N times with a sleep between), exactly as the spike's Python loop did. A built-in polling tool is a real ergonomics gap (§7) but is NOT in m5's contract — the test-orchestrated loop is the cheapest proof.
- **A `core.tap`-by-label selector tier.** The Flutter `core.tap` is `node_id`-only by design (§2); m5 does NOT add a label/xpath path to the Flutter side. It resolves the id from the observation and taps by id. Closing the core/native selector asymmetry, if ever desired, is its own milestone.

---

## 2. The driving approach (DECISION — not a fork)

**A hardware-gated dogfood e2e that drives the round-trip via `leonard_drive drive-dual invoke --tool native.*`/`core.*` against an `up`-held dual session, mirroring `drive_dual_e2e_test.dart`.**

The alternatives considered and rejected:

| Approach | Verdict |
|---|---|
| **(A) `drive-dual invoke` against an `up`-held dual session** | **Chosen.** Proves the **lenny harness** can do the round-trip (the milestone's whole point). Reuses m4's `up` + m3's `drive-dual` verbatim; adds zero new harness code. Each `invoke`/`observe` is a stateless attach→one-op→print→disconnect (the m3 front-door shape), so the test orchestrates the sequence + the adaptive poll the same way the spike's Python did. |
| (B) Raw Appium in the test (lift `o2_login.py` to Dart) | **Rejected.** Proves Appium can do it — already known (the spike is GREEN). Says nothing about the product. |
| (C) The autonomous LLM loop authenticates | **Rejected for m5** (§1.1 out-of-scope): model nondeterminism in a hardware-gated test; needs a provider + reward. Deferred. |

**Why (A) is the right altitude.** The bead's claim is "the **agent** taps Sign In → drives Auth0 → resumes on Flutter." The `drive-dual` front door is the deterministic, model-free substrate that an agent loop sits on top of: every `invoke` goes through `MultiHostSession.act` → namespace routing → the per-host `VmServiceClient.executeAction` → `ext.exploration.<ns>.<tool>` — the **exact** wire path the autonomous loop uses. A GREEN here means the harness's perceive-merge-route-act machinery does the full Auth0 loop; only the *chooser* (scripted vs model) differs from the autonomous variant. That is the strongest claim m5 can make without importing model flakiness into a hardware tier.

### 2.1 The core/native selector asymmetry — Step 1 is a TWO-CALL Flutter resolve

The two channels expose **different selector surfaces**, and m5 must drive across the gap:

- **`native.tap`** accepts a `NativeSelector` chain: `id | label | xpath | rect`. The Auth0 web buttons (consent, Continue, authorize) are reached by `label`/`xpath`.
- **`core.tap` (Flutter) takes `node_id` ONLY.** Verified against `packages/leonard_flutter/lib/src/core_tools/tools/tap_tools.dart`: `TapTool.inputSchema` is `{'node_id': {'type':'integer','minimum':1}}` with `required:['node_id']` and `additionalProperties:false`. There is **no** `label`/`xpath`/`rect` path on the Flutter side — that selector chain is `native.*`-only (via `NativeSelector`). A call like `core.tap --args '{"label":"Log in"}'` therefore can **never** return `ok:true` (the schema rejects the unknown property; `node_id` is missing).

So Step 1 is a **two-call resolve** against the held dual session:

1. **`drive-dual observe`** → scan the merged `observation['core']` for the node whose `label == 'Log in'`. The app sets `key: Key('login_button')` with `child: Text('Log in')` (`auth0_sample/lib/main.dart:64-68`), so the Flutter semantics `label` surfaces `'Log in'`. The core fragment serializes each node as `{id, …}` with `label` included when non-empty (`packages/leonard_flutter/lib/src/semantics/semantics_capture.dart:202-213` — `'id': id`, `if (label.isNotEmpty) m['label'] = label`). Take that node's integer `id`.
2. **`drive-dual invoke --tool core.tap --args '{"node_id":<id>}'`** → routed to the Flutter channel, dispatches `SemanticsAction.tap` (or a hit-test fallback) on the button → opens the OS `ASWebAuthenticationSession`.

This observe-then-tap-by-id pattern **IS the headline core→native handoff**: the agent perceives the Flutter tree, resolves the target by label-in-observation, taps it by id on `core`, and the live signal moves to `native`. Steps 2–6 (consent, email, password, Continue, Save-Password) are all `native.*` (the Auth0 web view lives outside the Flutter engine, in the `native` fragment). The switch from `core` to `native` and back to `core` is exactly the perception-driven context switch m3 built — m5 scripts it explicitly.

---

## 3. The round-trip steps mapped to harness tools (ordered)

Every step is a `leonard_drive drive-dual invoke`/`observe` against the held dual session (`--flutter-uri <flutterWs> --native-uri <nativeEndpoint>`). Selectors/values are the **exact** ones the live spike proved. The Auth0 page lives behind the `native` fragment; the app's own button + status live behind `core`.

### 3.0 Wire envelope — every assertion goes through `value`

`drive-dual invoke` prints `{tool, result}` (`packages/leonard_cli/bin/leonard_drive.dart:260` / `:424`), where `result` **IS** the canonical tool envelope. The envelope shape is fixed in `packages/leonard_contract/lib/src/dispatch.dart:44-48`: `{'ok': r.ok, 'value': r.value, 'error': r.error}`. The per-tool payload that `native.enter_text` returns — `via` / `readback` / `masked` — lives **inside `ToolResult.value`** (`packages/leonard_native/lib/src/native_extension.dart:218-220`), NOT at the top level.

**Therefore every assertion reads through `value`:**
- ok flag → `result['ok']`
- readback → `result['value']['readback']`
- masked → `result['value']['masked']`
- press key echo → `result['value']['key']`

Do **NOT** flatten to `result['readback']` / `result['masked']` — those keys do not exist at the top level (dispatch.dart:44-48). `drive-dual observe` prints `{observation: <merged Observation.toJson()>}` (`leonard_drive.dart:234` / `:416`); the merged observation is read at `result_of_observe['observation']`.

### 3.0a Fresh state — the Flutter app process MUST stay alive (no terminate, ever)

`up` holds a `flutter run` **attached to the app's VM service** (the `flutter_ws_uri` channel). The Auth0 sheet is presented **on top of** that still-running Flutter process (§1). The hard consequence:

- **The Flutter app process MUST NOT be terminated at any point in the round-trip.** Terminating the app (e.g. a raw Appium `terminate_app`) drops the VM-service connection `up` holds; `activate_app` then relaunches a **NEW** process that `flutter run` is NOT attached to, so `flutter_ws_uri` goes **DEAD** and every `core.*` step + the resume-observe fails. There is **no** post-`up` terminate/activate step in m5 — it would kill the channel the whole milestone depends on.
- **Re-run state hygiene is done BEFORE `up`, by uninstall** (not by terminate). In test setup, before `up`, do a **best-effort** `xcrun simctl uninstall <bundle>` on `com.nicospencer.lennyspike` (tolerate "not installed"). `up`'s `flutter run` then clean-installs a fresh app, so a prior run's typed text / error banner cannot persist. This is a single pre-`up` `xcrun` call, mirroring how m4 uses `xcrun simctl` above the seam.

> **RISK — Auth0 web-session persistence across runs (validate at build time).** `ASWebAuthenticationSession` may carry a sticky web session (cookies) across runs even after the app is uninstalled, so a re-run could skip the login form. This is a known **live-tier robustness concern to validate at build time**, not a correctness bug in this spec. The spike's `o2_login.py` terminate/activate is the proven-but-**INCOMPATIBLE-here** workaround — it dropped the raw Appium app, which in the dual design would drop the Flutter channel. The app-side fallback, if a sticky session bites, is `useEphemeralSession: true` on the app's `Auth0().webAuthentication(...)` call (a one-line change in the target app, not in lenny). The builder should confirm a fresh login form appears on a second consecutive run; if not, apply the `useEphemeralSession` fallback in the fixture app and note it.

### 3.1 Step table

| # | Action | Harness call | Notes (grounded in the spike + the app) |
|---|---|---|---|
| **0** | **Fresh-install prep (pre-`up`, in test setup).** | *(best-effort `xcrun simctl uninstall <bundle>` — NOT a tool, NOT post-`up`; see §3.0a)* | Clears stale install state so `up`'s `flutter run` clean-installs. **No terminate/activate of the running app — ever** (it would kill the Flutter channel, §3.0a). |
| **1a** | **Resolve the Flutter "Log in" node id.** | `observe` → scan `observation['core']` for the node with `label == 'Log in'` → take its integer `id` | `core.tap` is `node_id`-only (§2.1). The button is `ElevatedButton(key: Key('login_button'), child: Text('Log in'))` (`auth0_sample/lib/main.dart:64-68`); the semantics `label` surfaces `'Log in'`; the core fragment emits `{id, label}` (`semantics_capture.dart:202-213`). |
| **1b** | **Tap "Log in" (Flutter) by id.** | `invoke --tool core.tap --args '{"node_id":<id>}'` | Routes to the **Flutter** channel; `result['ok'] == true`. Opens the OS `ASWebAuthenticationSession`. After this the Flutter `core` goes quiet; the live signal moves to `native`. The Flutter process stays alive throughout (§3.0a). |
| **2** | **Accept the iOS consent sheet.** | `invoke --tool native.press --args '{"key":"consent_accept"}'` | Already wired: `AppiumBackend.press('consent_accept')` → `POST /session/{id}/alert/accept`. The consent sheet is a **SpringBoard process, NOT in `/source`** — an xpath find for "Continue" MISSES it; the alert endpoint is the only way. Assert `result['ok'] == true`. |
| **3** | **Clear+type email.** | `invoke --tool native.enter_text --args '{"xpath":"//XCUIElementTypeTextField[@name=\"Email address\"]","text":"<email>"}'` (text from `AUTH0_EMAIL`) | `enter_text` **clears before typing** inside the backend (`POST /clear` then `POST /value`, `appium_backend.dart:467-468`). Returns `value:{via, readback, masked:false}`. **Assert** `result['value']['readback'] == <email>` (email reads back exact) and `result['value']['masked'] == false`. |
| **4** | **Clear+type password.** | `invoke --tool native.enter_text --args '{"xpath":"//XCUIElementTypeSecureTextField[@name=\"Password\"]","text":"<password>"}'` (text from `AUTH0_PASSWORD`) | Same clear-before-type. Returns `value:{via, readback, masked:true}` — `masked` is **element-TYPE-derived** (`XCUIElementTypeSecureTextField` via `attribute/type`, NOT `readback != text`; `appium_backend.dart:489-503`). **Assert** `result['value']['masked'] == true` and `result['value']['readback'] != <password>` (defensive: assert non-empty + masked, **never** equality on a secure field). |
| **5** | **Tap Continue (sign in).** | `invoke --tool native.tap --args '{"xpath":"//XCUIElementTypeButton[@name=\"Continue\"]"}'` | The Auth0 sign-in button. After this, Auth0 may show an authorize/consent screen (step 6a) and iOS shows the Save-Password alert (step 6b). Assert `result['ok'] == true`. |
| **6a** | **Clear the Auth0 authorize screen (adaptive).** | `invoke --tool native.tap --args '{"label":"Accept"}'` (then `Allow` / `Authorize App` / `Authorize` as fallbacks) | Adaptive — appears only on first consent for the app/tenant. The test tries the label set in order, once; a miss (`result['ok'] == false`/no element) is a no-op (the screen wasn't shown). These ARE in `/source` (real Auth0 web buttons), so a `native.tap` by label works — no alert endpoint needed. |
| **6b** | **Dismiss the iOS Save-Password alert (adaptive).** | `invoke --tool native.press --args '{"key":"alert_dismiss"}'` ⟵ **NEW key, §4** | A **second** SpringBoard alert (NOT in `/source`), appearing AFTER sign-in. Currently **unhandled** by `press()` — m5 adds `alert_dismiss` → `POST /alert/dismiss` (§4). Adaptive: on iOS 26 sim it appears; if absent, `/alert/dismiss` returns a "no alert open" error which surfaces as `result['ok'] == false` — a **non-fatal no-op** for the test (the loop proceeds). |
| **7** | **Detect callback-return + resume-on-Flutter.** | `observe --policy action-relative` (polled) → inspect the **merged** observation's `core` fragment | The Auth0 callback (`com.nicospencer.lennyspike://…`) returns control to the **same** still-alive Flutter process; `_login()` sets `_status = 'logged in: <email>'` (`auth0_sample/lib/main.dart:50`), relighting the `Text(_status, key: status_text)` widget (line 70). **Assert** `jsonEncode(observation['core'])` contains `logged in: <email>` (§5). |

> **Ordering is critical** (spike risk): the Save-Password interstitial (6b) MUST be cleared *before* the resume poll concludes, and the authorize screen (6a) must be handled before Auth0 can redirect. The test runs 6a/6b inside the **same adaptive poll loop** as step 7 (try-dismiss-then-check-`core`) — not as fixed pre-poll steps.

---

## 4. The ONE native-tool gap — `press('alert_dismiss')` (minimal, behind the seam)

The round-trip needs to dismiss the iOS **Save-Password** SpringBoard alert (step 6b). The current surface does **not** cover it: `AppiumBackend.press` (verified in `appium_backend.dart`, the `press()` switch) recognizes only `consent_accept` (→ `/alert/accept`), `enter`/`return`/`done` (→ `/keys`), and `back` (Android); the `default` throws `NativeException('unknown press key: …')`. There is a `/alert/accept` path but **no `/alert/dismiss` counterpart** — exactly parallel to the consent gap the spike already proved.

**MINIMAL FIX (additive, behind the `NativeBackend` seam — no new tool, no new selector tier, no backend shape change):**

1. **`packages/leonard_native/lib/src/appium_backend.dart`** — add ONE case to `press()`, alongside `consent_accept`:
   ```dart
   case 'alert_dismiss':
     // iOS-only: dismiss a SpringBoard system alert (e.g. "Save Password?")
     // — a separate process NOT in /source, exactly parallel to consent_accept.
     // /alert/dismiss = the "Not Now" / cancel button.
     await _post('/session/$_sid/alert/dismiss', const <String, Object?>{});
     return;
   ```
   `_post` already throws `NativeException` on a "no alert open" body (the W3C error envelope, `_unwrap`), so an adaptive call when no alert is present surfaces as `result['ok'] == false` — a **non-fatal no-op** the test loop tolerates (mirrors `consent_accept`'s own no-alert behavior).
2. **`packages/leonard_native/lib/src/native_extension.dart`** — extend the `_PressTool.description` (lines 235-238) to mention `alert_dismiss` (iOS: dismiss a system alert, e.g. Save Password). No code change to the tool body: `_PressTool.call` (lines 251-263) already forwards any `key` to `backend.press` and returns `ToolResult(ok:true, value:{'key':key})` on success / `ToolResult(ok:false, error:e.message)` on `NativeException`.
3. **`packages/leonard_native/lib/src/native_backend.dart`** — extend the `press` doc-comment (lines 143-147) to list `alert_dismiss` alongside `consent_accept` (both iOS-only alert-endpoint keys). Doc-only.

No other native change. `enter_text`'s clear-before-type and the masked-readback semantics already match the recipe verbatim — **no change**. The authorize-screen (6a) buttons are real `/source` elements, so `native.tap` by label/xpath already handles them — **no change**.

> **Why a new `press` key, not an adaptive auto-dismiss inside `enter_text`/`tap`** (decided): keep the seam **explicit + minimal**. An implicit "probe for an alert and dismiss it" baked into every action would (a) add a `GET /alert/text` round-trip to the perception hot path, and (b) hide a side effect the model should choose. `alert_dismiss` mirrors the already-proven `consent_accept` exactly — one key, one endpoint, the model/test issues it adaptively. This is the smallest possible addition and stays a Tier-1-testable pure-key extension.

---

## 5. Resume-on-Flutter detection (the deeplink-return signal)

**The signal: the Flutter `core` fragment relights with the status `Text`.** When Auth0 redirects to `com.nicospencer.lennyspike://…/callback`, `auth0_flutter` completes `_auth0.webAuthentication(scheme: kScheme).login()`, control returns to the **same still-alive Flutter process** (§3.0a), and `_LoginPageState._login` runs `setState(() => _status = 'logged in: ${creds.user.email}')` (`auth0_sample/lib/main.dart:50`). That rebuilds `Text(_status, key: Key('status_text'))` (line 70), which the Flutter semantics tree surfaces — so the **merged observation's `core` fragment** now contains the string `logged in: <email>`.

**How it's observed + asserted (through the merged observation, NOT raw `/source`):**

- The test polls `leonard_drive drive-dual observe --policy action-relative --flutter-uri <flutterWs> --native-uri <nativeEndpoint>`, which emits `{observation: <merged Observation.toJson()>}` (`leonard_drive.dart:416`). The merged observation is m3's fold: `core` ← the Flutter channel's semantics; `extensions.native` ← the native fragment, side by side. The `status_text` widget lives in `core`. The observation is read at `result_of_observe['observation']`.
- **Primary assertion (resume):** `jsonEncode(observation['core']).contains('logged in: <email>')` is true (`<email>` is the `AUTH0_EMAIL` value). The status string may land in a node's `label`/`value`/text field depending on how the semantics serialize `Text`, so the test scans the encoded `core` JSON for the substring, not one hardcoded path — robust to the exact node shape, mirroring how the spike scans the raw source for `logged in`.
- **Secondary assertion (dual-attach still live):** `observation['extensions']` still contains the `native` key — proving the merged observation is well-formed (both channels attached) at the moment of resume.
- **Verdict gating:** the poll loop terminates with `verdict = 'LOGGED_IN'` when `logged in` appears in `core`; `'BAD_CREDS'` if `wrong email or password` appears in the merged observation (a hard test failure — surfaces a creds/env problem); `'TIMEOUT'` after the bounded poll budget (§6). The test asserts `verdict == 'LOGGED_IN'`.

> **Why `core`, not the `native` fragment:** at resume the Auth0 web view is gone and the native `/source` is the bare app shell; the authenticated signal is a **Flutter** widget, so it MUST come from `core`. This is precisely the m3 "context switch back to Flutter" the merge was built to expose — m5 is its first real assertion. The deeplink-return is observed *as a Flutter `core` relight*, which is the bead's pinned "resume-on-Flutter" signal (route/riverpod/callback all reduce to: the Flutter tree lit up with the authenticated status).

---

## 6. Creds, secrets, gating & STOP conditions

**Credentials via ENV — never hardcoded, never recorded in the repo, never logged.** The operator supplies the live Auth0 credentials **out-of-band via environment variables**; the live values are **NOT** stored anywhere in this repo or its git history. Only the env-var **names** appear in this document. The test reads them at start, passes them as `--args` JSON to the `drive-dual invoke` subprocess, and never writes them to the trajectory/log.

| Env var | Purpose |
|---|---|
| `AUTH0_EMAIL` | the Auth0 login email (step 3 + the resume assertion substring). Operator-supplied; value `<operator-supplied>`. |
| `AUTH0_PASSWORD` | the Auth0 password (step 4). Operator-supplied; value `<operator-supplied>`. |

The reused m3/m4 env vars (the hardware tier — same names, verbatim):

| Env var | Purpose |
|---|---|
| `LEONARD_NATIVE_APPIUM_SERVER` | Appium base URL (default `http://127.0.0.1:4723`). |
| `LEONARD_NATIVE_SIM_UDID` | the booted iOS sim udid (shared device identity). |
| `LEONARD_NATIVE_APP` | the built `Runner.app` path (the lenny-instrumented `auth0_sample`). |
| `LEONARD_NATIVE_FLUTTER_PROJECT` | the Flutter project root (cwd for `up`). |
| `LEONARD_NATIVE_FLUTTER_TARGET` | the Flutter entrypoint (`lib/main.dart`). |

**Hardware-gated self-skip (the house rule — two-stage, mirrors `drive_dual_e2e_test.dart`):**

1. **Sync env gate at `main()`-time** (`_envSkipReason`): require `LEONARD_NATIVE_SIM_UDID` + `LEONARD_NATIVE_APP` (must exist on disk) + `LEONARD_NATIVE_FLUTTER_PROJECT` (must have `pubspec.yaml`) + `LEONARD_NATIVE_FLUTTER_TARGET` + **`AUTH0_EMAIL` + `AUTH0_PASSWORD`**. `markTestSkipped(reason)` + `return` when any is absent — a **synchronous** check (no HTTP), so the default `melos run test` / `dart test` is safe and self-skips.
2. **Async Appium reachability probe INSIDE the test body** (`_appiumReachable`): `GET <server>/status` (3s connect / 5s read), `markTestSkipped` when Appium is down. (An HTTP probe in a sync `main()` gate would `sleep`-deadlock the isolate and always skip — m4's rule. Copy `_appiumReachable` verbatim from `drive_dual_e2e_test.dart`.)

**STOP conditions (bounded — never hang):**
- The resume poll budget is **bounded**: 16 polls × 2s = ~32s, under the `@Timeout(Duration(seconds: 300))` test cap (matching m3's e2e). On `TIMEOUT`, the test FAILS with the captured `up` stdout + the last merged observation for triage.
- `up` readiness has a 240s timeout on the `vm_service_ready` line (matching `drive_dual_e2e_test.dart`).
- **Teardown in `finally`** (always runs): `down --pid-file <P>` (tears both channels via m4's `DualLaunchHandle.shutdown`), `up.kill(SIGKILL)`, temp-dir cleanup. The Appium **server** is never stopped (attach). There is **no** raw-Appium session to clean up — m5 owns none (§3.0a removed the hygiene session entirely; the only raw `xcrun` call is the pre-`up` uninstall, which leaves no open session).
- **Creds hygiene:** `AUTH0_PASSWORD` is readable in process listings (it rides `--args` to a `drive-dual invoke` subprocess); the test must run only on trusted machines, and the operator's Auth0 account should be a low-privilege throwaway. The values are never written to the trajectory/log and never committed. Auth0 rate-limits repeated logins — keep a small inter-run delay; do NOT run this e2e in parallel.

---

## 7. The fixture decision (THE one human-review fork — flagged)

**The open question (pinned by the bead):** the e2e target app (the lenny-instrumented `auth0_sample`) lives in `~/lenny-spike/auth0_sample` today and is referenced only via `LEONARD_NATIVE_APP` / `LEONARD_NATIVE_FLUTTER_PROJECT` env paths. Do we **(A)** commit it into the lenny repo as a reproducible fixture, or **(B)** keep it external in `~/lenny-spike`?

| Option | Pros | Cons |
|---|---|---|
| **(A) Commit as a repo fixture** (e.g. `examples/auth0_sample`) | Reproducible CI; the `Runner.app` build is self-contained; the instrumentation (`leonard_flutter` + `LeonardBinding.ensureInitialized`) is version-pinned with the repo; a new dev can build + run the e2e without the spike dir. | Adds an `auth0_flutter` dep + a real **Auth0 tenant/clientId** to the repo (the sample hardcodes `kDomain`/`kClientId` at `auth0_sample/lib/main.dart:10-11` — a live tenant in source); larger repo; another Flutter app in the workspace to keep building green. |
| **(B) Keep in `~/lenny-spike`** (status quo) | Lighter; matches the spike + m3/m4's hardware tier; no live-tenant config in the repo; the e2e is env-path-driven and already self-skips when the paths are absent (so default CI is unaffected either way). | Not reproducible without the spike dir; the instrumentation can drift from the repo's `leonard_flutter` version unnoticed; "build the target" is an undocumented operator step. |

**RECOMMENDATION: (B) — keep it external for m5, env-path-driven**, exactly as m3/m4's hardware tier already does (those e2es point `LEONARD_NATIVE_APP` at the same external `Runner.app` and self-skip). Reasons: (1) m5's e2e is **already** hardware-gated and self-skipping — a committed fixture does not make the *default* gate any more reproducible (it still needs a sim + Appium + a real Auth0 round-trip, which CI does not have); the fixture only helps a human who is *running* the live tier, and that human already has the spike dir. (2) Committing the sample drags a **live Auth0 tenant + clientId into source** (`auth0_sample/lib/main.dart:10-11`) — a real-account coupling that wants a deliberate decision, not a side effect of m5. (3) It keeps m5 a **one-package, two-file** change (the e2e + the melos entry + the one `press` key) instead of also onboarding + maintaining a second Flutter app. The e2e is byte-for-byte identical either way (the env-path indirection means the test never references the fixture location). Promotion to `examples/` is an **independent, additive follow-up bead** — file it; it does not block or change m5's e2e.

> **This is the ONE human-review fork** (mirroring how m4-spec §2 framed its `--boot-sim` fork). Everything else in this spec is independent of it: the e2e reads the app via `LEONARD_NATIVE_APP` / `LEONARD_NATIVE_FLUTTER_PROJECT` regardless of where those paths point. Flip to (A) by adding the sample under `examples/` and pointing the env vars there — no test change.

---

## 8. Acceptance Criteria

Each is independently verifiable; the HOW + tier is named. **T1** = unit/wiring (default `melos run test`, no device); **T2** = live dogfood (hardware-gated, **self-skips** when env/Appium absent). Because m5 is fundamentally an e2e milestone, the ACs are mostly T2; the one new native key gets T1 unit coverage.

1. **`press('alert_dismiss')` issues `POST /alert/dismiss` (new key, behind the seam).** *Check (T1, `packages/leonard_native/test/appium_backend_test.dart`):* with a fake `http.Client`, `AppiumBackend.press('alert_dismiss')` posts to `/session/<sid>/alert/dismiss` with an empty body; a "no alert open" error envelope surfaces as a `NativeException` (so the tool returns `{ok:false}`), NOT a crash. Mirror the existing `consent_accept` → `/alert/accept` test vector.
2. **`native.press` exposes `alert_dismiss` end to end.** *Check (T1, `packages/leonard_native/test/native_extension_test.dart`):* `_PressTool.call({'key':'alert_dismiss'})` forwards to `backend.press('alert_dismiss')` and returns `ToolResult(ok:true, value:{'key':'alert_dismiss'})` on success; the tool description string mentions `alert_dismiss`. (Mirrors the existing `consent_accept` press-tool test at `native_extension_test.dart:315`.)
3. **The dogfood e2e self-skips cleanly with no env (default gate stays green).** *Check (T1, by running the file with no env):* `dart test packages/leonard_cli/test/dogfood_auth0_e2e_test.dart` reports ONE skipped test (the sync env gate fires; no subprocess, no HTTP). Verifies the house-rule gate.
4. **The e2e self-skips when Appium is down (env present).** *Check (T2-adjacent, run with env set but Appium stopped):* the async `_appiumReachable` probe fails → `markTestSkipped` → one skipped test, no boot.
5. **`up` boots the dual session and the e2e taps Log in on the Flutter channel via observe-then-node_id.** *Check (T2):* the e2e `up`s the native dual path, parses one `vm_service_ready` line (asserts `flutter_ws_uri` + `native_endpoint`), runs `drive-dual observe`, finds the `core` node with `label == 'Log in'`, then `drive-dual invoke --tool core.tap --args '{"node_id":<id>}'` returns `{tool:'core.tap', result:{ok:true,…}}` (routed to Flutter, opens Auth0). The `core.tap`-by-`node_id` is what returns `ok:true` — a `core.tap` by `label` would be rejected by the schema (§2.1).
6. **Consent is accepted via the native alert endpoint.** *Check (T2):* `drive-dual invoke --tool native.press --args '{"key":"consent_accept"}'` returns `result['ok'] == true`; a subsequent `observe` shows the Auth0 form in `extensions.native` (the consent sheet is gone, the email/password fields are present).
7. **Email types and reads back exact (clear-before-type, fresh install).** *Check (T2):* `drive-dual invoke --tool native.enter_text` with the email xpath returns `result['value']['readback'] == <AUTH0_EMAIL>` and `result['value']['masked'] == false`.
8. **Password types and reads back masked (element-type-derived).** *Check (T2):* `drive-dual invoke --tool native.enter_text` with the password xpath returns `result['value']['masked'] == true` and `result['value']['readback'] != <AUTH0_PASSWORD>` (assert non-empty + masked, NOT equality on a secure field).
9. **Continue + the adaptive authorize/Save-Password handling drive sign-in to completion.** *Check (T2):* after `native.tap` Continue, the test's adaptive loop (authorize-tap once + `native.press alert_dismiss` per poll) clears both interstitials; the run reaches `verdict == 'LOGGED_IN'` (not `BAD_CREDS`/`TIMEOUT`).
10. **Resume-on-Flutter: the merged `core` fragment relights with the authenticated status.** *Check (T2):* a `drive-dual observe` after callback-return yields a merged observation whose `jsonEncode(observation['core'])` contains `logged in: <AUTH0_EMAIL>` — proving the deeplink returned control to the still-alive Flutter process and the status `Text` is observable through the merged observation (NOT raw `/source`).
11. **The dual attach is still well-formed at resume.** *Check (T2):* the same resume observation's `observation['extensions']` still contains the `native` key (both channels attached; the merge is intact).
12. **The Flutter app process is never terminated; fresh state comes from pre-`up` uninstall.** *Check (T2):* the e2e contains **no** raw-Appium `terminate_app`/`activate_app` call; the only `xcrun` is a best-effort `simctl uninstall <bundle>` in setup BEFORE `up`. `down --pid-file P` → `up` exits 0, emits `{event:'shutdown'}`. (Reuses m4's `DualLaunchHandle.shutdown`.) The Flutter channel stays live for the whole round-trip (§3.0a).
13. **`feat/leonard-native` base; `melos run analyze` + `format` clean; no new runtime dep.** *Check (T1):* the only library change is the additive `press` key in `leonard_native` (no new package dep); `leonard_cli` gains one test file + the melos `test:e2e:auth0` script; `melos run analyze` + `melos run format` pass.

---

## 9. Implementation Plan (file-by-file, ordered)

On `feat/leonard-native`.

### `packages/leonard_native` (the one minimal seam addition)

1. **`lib/src/appium_backend.dart`** — add the `case 'alert_dismiss':` arm to `press()` (§4): `await _post('/session/$_sid/alert/dismiss', const <String,Object?>{}); return;`. One arm, alongside `consent_accept`.
2. **`lib/src/native_extension.dart`** — extend `_PressTool.description` (lines 235-238) to mention `alert_dismiss` (iOS: dismiss a system alert, e.g. Save Password). Doc-string only — `_PressTool.call` already forwards any `key`.
3. **`lib/src/native_backend.dart`** — extend the `press` doc-comment (lines 143-147) to list `alert_dismiss` as an iOS alert-endpoint key alongside `consent_accept`. Doc only.
4. **`test/appium_backend_test.dart`** — add the AC1 vector (`alert_dismiss` → `/alert/dismiss`; no-alert error → `NativeException`), mirroring the `consent_accept` test.
5. **`test/native_extension_test.dart`** — add the AC2 vector (`_PressTool` forwards `alert_dismiss`; description mentions it), mirroring the `consent_accept` press-tool test at line 315.

### `packages/leonard_cli` (the dogfood e2e + melos entry)

6. **`test/dogfood_auth0_e2e_test.dart`** (NEW, T2) — the hardware-gated Auth0 round-trip e2e (§3 + §5 + §6), **modeled on `drive_dual_e2e_test.dart`**:
   - Copy the env-gate + `_appiumReachable` + `_hostScript` + `_findPackageRoot` helpers from `drive_dual_e2e_test.dart` verbatim; add the `AUTH0_EMAIL`/`AUTH0_PASSWORD` env requirements to `_envSkipReason`.
   - **Setup — fresh install** (§3.0a): best-effort `xcrun simctl uninstall com.nicospencer.lennyspike <udid>` (tolerate "not installed") BEFORE `up`. **No terminate/activate of a running app — ever.**
   - `up` the dual path (`--runner flutter -t <FLUTTER_TARGET> --udid <UDID> --app <APP> --native-host <host> --appium-server <server> --pid-file P --uri-file F`, cwd `LEONARD_NATIVE_FLUTTER_PROJECT`); parse `vm_service_ready` → `flutterWs` + `nativeEndpoint`.
   - **Step 1 (resolve + tap)** (§2.1): `drive-dual observe` → find the `core` node with `label == 'Log in'` → take its `id` → `drive-dual invoke --tool core.tap --args '{"node_id":<id>}'`; assert `result['ok'] == true`.
   - **Steps 2–5** (§3): a sequence of `Process.run(... 'drive-dual','invoke','--flutter-uri',flutterWs,'--native-uri',nativeEndpoint,'--tool',<t>,'--args',<json>)`, asserting routed exit 0 + the per-step `result['value']` fields (`readback`/`masked`, §3.0).
   - **Step 7 adaptive poll** (§5): up to 16× — `native.press alert_dismiss` (tolerate `result['ok'] == false`) + a `native.tap` authorize-label probe (once) + a `drive-dual observe`; read `observation` at `result_of_observe['observation']`; scan the merged `observation['core']` JSON for `logged in: <AUTH0_EMAIL>`; break on found (`verdict='LOGGED_IN'`) or `wrong email or password` (`verdict='BAD_CREDS'`); 2s sleep between.
   - Assert AC10/AC11/AC12; `down --pid-file P`; teardown in `finally` (SIGKILL `up`, temp cleanup). `@Timeout(Duration(seconds: 300))`.
   - Drain BOTH stdout + stderr of every spawned process (full-pipe gotcha).
7. **`pubspec.yaml` (workspace root, `melos.scripts`)** — add a `test:e2e:auth0` script mirroring `test:e2e`:
   ```yaml
   test:e2e:auth0:
     description: >-
       Run the live Auth0 round-trip dogfood e2e (leonard_native m5). Requires a
       booted iOS sim + Appium + LEONARD_NATIVE_* and AUTH0_EMAIL/AUTH0_PASSWORD.
       Self-skips when absent, so it is safe to invoke locally.
     run: >-
       dart test packages/leonard_cli/test/dogfood_auth0_e2e_test.dart
   ```

**Load-bearing constraints (carry from m3/m4 / project rules):**
- The e2e drives **only** through `leonard_drive drive-dual` (the harness), never raw Appium. The single non-tool OS call is the pre-`up` `xcrun simctl uninstall` (app-state prep, not perceive/drive). m5 owns **no** raw Appium session.
- **The Flutter app process must stay alive for the whole round-trip** (§3.0a) — no terminate/activate; that would kill `flutter_ws_uri` and break every `core.*` step + the resume-observe.
- `core.tap` is `node_id`-only (§2.1) — resolve the id from the observation; never pass `label` to `core.tap`.
- All `enter_text` assertions read through `result['value']` (§3.0) — `result['value']['readback']` / `result['value']['masked']`, never the flattened top level.
- `enter_text` clears before typing inside the backend (`/clear` then `/value`) — the test does NOT pre-clear and must NOT append.
- `masked` is element-type-derived — never assert equality on the password readback.
- The resume signal is in the merged **`core`** fragment, never the native fragment (the Auth0 web view is gone at resume).
- `leonard_agent` is untouched (m3 owns `MultiHostSession`); the only library change is the additive `press` key in `leonard_native`.

---

## 10. Validation Plan

Exactly **two tiers**, mirroring the package convention + the **test-taxonomy house rule** (a faked/stubbed boundary is unit; a live device is e2e — never name a faked test `*_e2e_test.dart`).

### Tier 1 — UNIT (default `melos run test`, no device)
- **`packages/leonard_native/test/appium_backend_test.dart`** — AC1 (`alert_dismiss` → `/alert/dismiss`; no-alert → `NativeException`) on a fake `http.Client`.
- **`packages/leonard_native/test/native_extension_test.dart`** — AC2 (`_PressTool` forwards `alert_dismiss`; description string).
- The new e2e file itself, run with NO env, satisfies AC3 (one skipped test, no boot) — this is the default-gate safety check.

### Tier 2 — LIVE dogfood Auth0 e2e (hardware-gated, self-skips)
`packages/leonard_cli/test/dogfood_auth0_e2e_test.dart` — AC4–AC12, the full round-trip:
- **Sync env gate** at `main()` (`LEONARD_NATIVE_*` + `AUTH0_EMAIL` + `AUTH0_PASSWORD`); **async Appium probe** in the body. Self-skips when the live tier is absent.
- **Drive shape:** pre-`up` `xcrun simctl uninstall <bundle>` → `up` dual → `observe` + resolve `core` "Log in" node id → `core.tap node_id` → `native.press consent_accept` → `native.enter_text` email (readback exact) → `native.enter_text` password (masked) → `native.tap` Continue → adaptive (`native.tap` authorize / `native.press alert_dismiss`) + `drive-dual observe` poll until merged `core` shows `logged in: <email>` → assert resume + native-still-attached → `down`. **No terminate/activate — the Flutter process stays alive throughout.** Teardown in `finally`, SIGKILL escalation, temp cleanup.
- Run it: `melos run test:e2e:auth0` (or `dart test packages/leonard_cli/test/dogfood_auth0_e2e_test.dart`) with the env + a booted sim + Appium.

**Quality gates before handoff:** `melos run analyze`, `melos run test` (the hardware tier self-skips locally → default gate stays green for everyone), `melos run format`. Land to `feat/leonard-native` only (project landing flow: factory lands direct-to-branch on analyze-and-test green; `git push`, do not hand-roll a PR).

---

## Key constraints / gotchas the builder must respect

- **Drive through the harness, not raw Appium** — every perceive/drive step is `leonard_drive drive-dual`; the ONLY non-tool OS call is the pre-`up` `xcrun simctl uninstall` (app-state prep). m5 owns no raw Appium session. The point of m5 is to prove the **product** does the round-trip.
- **The Flutter app process MUST stay alive the whole round-trip** — `up` holds `flutter run` attached to its VM service (`flutter_ws_uri`); the Auth0 sheet is presented on top of that live process. **NO terminate/activate, ever** — it would drop the channel and break every `core.*` step + the resume-observe. Fresh state comes from a pre-`up` `simctl uninstall` (§3.0a).
- **Step 1 "Log in" is a TWO-CALL Flutter resolve** — `core.tap` is `node_id`-only (`tap_tools.dart:21-28`); `core.tap` by `label` can never be `ok:true`. Observe → find the `core` node with `label == 'Log in'` → tap by its integer `id`. This is the headline core→native handoff and exposes the core/native selector asymmetry (`native.*` accepts id|label|xpath|rect; `core.*` is node_id-only).
- **Every result field is under `value`** — the wire envelope is `{ok, value, error}` (`dispatch.dart:44-48`); `drive-dual invoke` prints `{tool, result}` where `result` is that envelope. Assert `result['ok']`, `result['value']['readback']`, `result['value']['masked']` — never the flattened top level.
- **`alert_dismiss` is the ONLY new code** — one `press()` arm → `POST /alert/dismiss`, parallel to the proven `consent_accept` → `/alert/accept`. No new tool, no selector tier, no backend shape change. Adaptive call when no alert is open → `NativeException` → `result['ok'] == false` → test no-op (non-fatal).
- **`enter_text` clears before typing inside the backend** (`/clear` then `/value`, `appium_backend.dart:467-468`) — the test must NOT pre-clear and must NOT append.
- **`masked` is element-TYPE-derived** (`XCUIElementTypeSecureTextField` via `attribute/type`, `appium_backend.dart:489-503`) — assert `masked==true` + readback non-empty + `readback != password`; NEVER equality on a secure field.
- **The consent sheet AND the Save-Password alert are SpringBoard processes, NOT in `/source`** — both go through the W3C alert endpoint (`consent_accept`/`alert_dismiss`), never xpath. The authorize screen (6a) IS in `/source` (real Auth0 buttons) → `native.tap` by label.
- **The Save-Password alert is ADAPTIVE** (iOS-version / credential-manager dependent) — `alert_dismiss` when absent is a non-fatal no-op; the test handles it inside the poll loop, not as a fixed step.
- **Resume signal is the merged `core` fragment** — `jsonEncode(observation['core']).contains('logged in: <email>')`. The status `Text(key: status_text)` is a Flutter widget; at resume the native `/source` is the bare shell. Scan the JSON for the substring (robust to node serialization), do NOT hardcode a node path.
- **Creds via ENV only** (`AUTH0_EMAIL`/`AUTH0_PASSWORD`); never hardcode, never log, never commit — the operator supplies them out-of-band; only the env-var names appear in source. `AUTH0_PASSWORD` rides `--args` to a subprocess (visible in `ps`) — run only on trusted machines; use a low-privilege throwaway account. Auth0 rate-limits — small inter-run delay, no parallel runs.
- **Bounded everything — never hang**: 16×2s resume poll (~32s) under `@Timeout(300s)`; 240s `up`-ready timeout; teardown in `finally` (SIGKILL `up`, temp cleanup). The Appium server is never stopped (attach).
- **Two-stage gate (house rule)**: sync env check at `main()` (no HTTP — an HTTP probe in a sync gate `sleep`-deadlocks and always skips); async Appium probe in the test body. Copy `_appiumReachable` verbatim from `drive_dual_e2e_test.dart`.
- **`feat/leonard-native` base; `leonard_agent` untouched** — m3 owns `MultiHostSession`/merge/route; m4 owns the launch lifecycle. m5 only consumes them + adds one `press` key + one e2e + one melos script.
