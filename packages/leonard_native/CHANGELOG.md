## 0.3.1

- **Fixed: the `resourceId` tier can now resolve Chrome web-content fields
  (bare HTML ids).** UiAutomator2's `using=id` locator only consults real
  view resource names (`pkg:id/name`); the `resource-id` you see on a web
  `<input>` is synthesized from its HTML `id` when the tree is serialized, so
  it was present in `/source` yet invisible to the live selector — and since
  `resourceId` is tier 1 and often the only populated tier, the miss consumed
  the full retry window and read as a device timeout rather than a wrong
  locator. On a `using=id` miss, a BARE value (no `:id/`) now falls through
  to `//*[@resource-id='…']` over the serialized tree and reports
  `via: 'resource-id-xpath'`; a missed `pkg:id/name` is a genuine miss and
  does not fall through. Verified live against real Chrome on device
  (SM-M225FV) alongside an unchanged native-id resolution. Reported on
  https://github.com/memento-engineering/lenny/issues/51.

## 0.3.0

- **Breaking — `NativeBackend.connect()` takes `extraCapabilities`.** The
  abstract contract is now
  `Future<void> connect({Map<String, Object?> extraCapabilities = const {}})`
  on both `UiAutomator2Backend` and `XcuiTestBackend`: the map is merged over
  the orthogonal Appium defaults when a new session is created, and
  attach-critical capabilities are rejected with `ArgumentError`. Migration:
  an external `NativeBackend` implementer adds the named parameter (a
  delegating implementation only changes its signature); existing call sites
  are source-compatible.
- **Breaking — `XcuiTestBackend` gains attach-by-bundle-id and stops forcing
  `appium:app`.** `XcuiTestBackend.attach(udid: …, bundleId: …)` attaches to
  an already-running app instead of always launching from an `.app` path; the
  default constructor keeps launch mode. Migration: code that relied on
  `appium:app` being unconditionally present must use launch mode explicitly.
- `NativeSelector` gains a `resourceId` tier — on Android it resolves first
  (`resource-id` is the strongest handle the platform offers); on iOS, which
  has no analogue, the tier is skipped. Additive.
- `NativeSelector.flutterIdentifier('x')` selects a Flutter
  `Semantics(identifier:)` widget through the Android channel. It expands to
  `//*[@resource-id='x']/ancestor-or-self::*[@clickable="true"][1]`, which is
  correct on BOTH measured projection shapes — Pixel 7a / Android 16 puts the
  identifier on a non-clickable wrapper, an SM-M225FV / Android 13 projects it
  clickable-self; both captures are recorded in the README so neither gets
  hardcoded. Additive.
- **Android permission dialogs are a first-class obstruction.**
  `press('dismiss_overlay')` REFUSES them, because Android Back denies the
  permission — denial persistently changes application behaviour, and granting
  was not requested either. Consumers state intent explicitly with the new
  `permission_allow` / `permission_deny` press keys. Behaviour change with
  additive API; proven against a live device
  (`android_permission_dialog_proof.dart`).

- **Docs — CORRECTION to 0.2.2's migration note, which was wrong for one
  consumer shape.** 0.2.2 said, unqualified: *"Remove consumer-owned
  Touch-To-Fill dismissal logic: it is redundant."* That holds only for
  consumers driving the Leonard **tool** surface, where `enter_text` owns
  recovery. A consumer holding a `NativeBackend` **directly** gets only a throw:
  `UiAutomator2Backend.enterText` detects the obstruction and raises
  `NativeException` with `NativeException.fieldObscuredCode`, and never
  recovers — at that seam it holds an already-resolved `NativeTarget` and cannot
  re-resolve the handle that dismissal invalidates. Recovery lives in
  `_EnterTextTool`, the layer that holds the selector.
  If you deleted your dismissal on 0.2.2's advice and drive the backend
  directly, reinstate it — the recipe is now in the dartdoc on
  `NativeException.fieldObscuredCode` and in the README. Your reinstated version
  should be strictly better than what you deleted: branch on
  `fieldObscuredCode` rather than message text, and dismiss via
  `press('dismiss_overlay')`, which is positively gated inside the backend, so
  the destructive bare-`back` hazard is handled upstream instead of in each
  consumer's gating discipline.
  No runtime behaviour changed in this release. Reported on
  https://github.com/memento-engineering/lenny/issues/26.
- **`NativeException.elementGoneAfterDismissalCode`** — a documented code for
  "the obstruction cleared, but the element is gone". The recovery recipe threw
  that outcome as a bare, code-less `NativeException`, which pushed consumers who
  had just been taught to branch on `code` back to string-matching the message.
  Additive; nothing existing changes.
- **Docs — the recovery recipe now preserves the original cause when dismissal
  fails.** As first drafted, the recipe left `press('dismiss_overlay')`
  unwrapped, so a failed dismissal replaced the obstruction error. That diverged
  from `_EnterTextTool`, which deliberately keeps the original. It matters
  because `dismiss_overlay` is positively gated and throws `no dismissible
  platform overlay is present` when the overlay has already cleared — reachable
  as a race, since Chrome dismisses the sheet on its own timers and the sheet is
  once-per-page rather than once-per-field. The unwrapped form therefore reported
  broken-looking recovery instead of the real cause, precisely in the case where
  the cause is hardest to guess. `overlay_recovery_recipe_test.dart` now pins
  this alongside the step order. Reported on
  https://github.com/memento-engineering/lenny/pull/32.
- **Docs — `NativeBackend.resolve` documents its internal retry.** The cost is
  **per populated tier**, not per call: a tier whose selector field is null is
  skipped outright, and each tier that does issue an element find carries its own
  ~10 s retry window. So an xpath-only selector that matches nothing costs ~10 s,
  while one carrying an a11y-id, a label *and* an xpath that all miss costs
  **~30 s inside a single call** — the worst case. Tier 2 only issues a find when
  the cached snapshot already has a label match, and tier 4 (rect-center) makes
  no device round-trip at all. An outer retry loop multiplies against whichever
  figure applies — 20 attempts against a fully-missing selector is ~10 minutes,
  which presents as a hang rather than a failure. Callers polling for a condition
  should detect it directly rather than discover it through a resolve failure,
  and keep outer counts small.

## 0.2.2

- **Behaviour change — Chrome credential sheets auto-recover:** `enter_text`
  now detects a positively identified Chrome bottom sheet after an obstructed
  write, dismisses it, re-resolves the invalidated element handle, and retries
  once. Remove consumer-owned Touch-To-Fill dismissal logic: it is redundant.
  Any transitional consumer dismissal must remain positively gated because a
  second bare Android `back` navigates the Custom Tab away. If detection or
  dismissal fails, the existing cause-bearing error remains the final result.
  The detection probe itself fails safe toward NOT acting: an unreadable or
  malformed `/source` reads as "nothing obstructing", so an obstructed write
  still falls through to the pre-existing click + `mobile: type` fallback
  rather than aborting on a transient read.

- **Fix (destructive):** `UiAutomator2Backend`'s keyboard dismiss no longer
  fires a bare `POST /back`. It now probes
  `appium/device/is_keyboard_shown` first and presses nothing when no soft
  keyboard is up. `back` is Android's dismiss gesture only while a keyboard
  holds focus; with none up it is plain navigation, and since `setValue` /
  `mobile: type` do not raise the soft keyboard, the old unconditional press
  navigated a Chrome Custom Tab AWAY at the end of every successful
  `enterText` — stranding the flow, because later field lookups then 404
  against a page that is no longer showing. If the keyboard state cannot be
  read, nothing is pressed: a keyboard left up is recoverable, a spurious
  back is not. This brings Android in line with the iOS impl, which already
  probed for a `Done` key before clicking.
- `NativeNode` gains `resourceId`, the Android `resource-id` (null on iOS,
  where XCUITest has no analogue — its `identifier` is already carried by
  `a11yId`). It is the only stable, non-localising way for a Dart consumer to
  identify a platform overlay: Chrome's Touch-To-Fill sheet is matched by
  `touch_to_fill_sheet_title` / `bottom_sheet`, while its title text,
  content-desc and per-row summary all localise, so string matching breaks on a
  non-English device.
  Deliberately NOT added to `toRecord()`: that record is the canonical
  cross-host schema and stays byte-identical to `leonard_flutter`'s semantics
  fragment, which has no resource-id to emit. The model addresses nodes by
  `identifier`/`label`, so the wire shape is unchanged and no snapshot
  expectations move.
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
