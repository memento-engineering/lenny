# leonard_native

A pure-Dart Leonard contract extension that lets the target-agnostic Leonard
driver perceive and drive a **native mobile app** (iOS first) over the
unchanged `ext.leonard.*` surface — by observing the OS accessibility tree
(via Appium/XCUITest) instead of a Flutter widget tree or a tmux server.

This is the native analogue of `leonard_tmux`:

| tmux | native |
|---|---|
| `TmuxExtension` | `NativeExtension` |
| `TmuxObservation` | `NativeSnapshot` |
| `TmuxPerception` | `NativePerception` |
| `TmuxClient` seam | `NativeBackend` seam |
| `ProcessTmuxExecutor` | `XcuiTestBackend` |

`NativeExtension` exposes four tools — `native.tap`, `native.enter_text`,
`native.press`, `native.swipe` — and projects the a11y tree into the
`extensions.native` observation fragment. The fragment uses the same canonical
per-node record schema as the Flutter semantics fragment
(`{id, role, rect, label?, value?, state?, actions?, scroll?}`).

## Running the host

The host runner serves the `native` extension over the VM service. It expects
an **already-running** Appium server and an **already-booted** iOS simulator
(it does NOT boot either):

```bash
dart run --enable-vm-service=0 --disable-service-auth-codes \
  bin/leonard_native_host.dart \
  --udid <booted-sim-udid> --app /path/to/Runner.app
```

It prints `LEONARD_HOST_READY` once installed; point a `LeonardSession` (or
`leonard_cli` / `leonard_drive`) at the printed VM-service ws URI.

Args:

- `--server <url>` — Appium server (default `http://127.0.0.1:4723`)
- `--udid <udid>` — booted simulator udid (required)
- `--app <path>` — path to the `.app` bundle (required)
- `--platform ios` — target platform (default `ios`)

### iOS simulators on Xcode 27: XCUITest driver 12 or newer

On Xcode 27 the simulator UI is no longer Simulator.app but DeviceHub
(`Xcode.app/Contents/Applications/DeviceHub.app`, bundle id
`com.apple.dt.Devices`). Appium's XCUITest driver **11.x and older** only looks
for Simulator.app, decides the booted simulator is headless, and on session
create **reboots it** "with the Simulator window visible". That kills the app
under test even with attach-safe capabilities, so an attach comes up on the
home screen. Use **XCUITest driver 12.x or newer** (verified: 12.13.2, which
bundles `appium-ios-simulator` 10.1.1 and recognises DeviceHub):

```bash
appium driver update xcuitest
```

Driver 12 is ESM and imports `appium` as a peer. When the Appium server is
installed globally (for example through Volta), the driver fails to load with
`Cannot find package 'appium' imported from …/appium-xcuitest-driver/…` until
`appium`, at the server's own version, is installed into `APPIUM_HOME`:

```bash
cd ~/.appium && npm install --save-dev appium@$(appium --version)
```

`XcuiTestBackend.attach` checks for this after session create: if the driver
reports the attached bundle is no longer running, `connect()` throws a
`NativeException` naming this cause, instead of leaving you driving the home
screen.

## Selecting Flutter widgets through the native channel on Android

Flutter's projection into Android's accessibility tree is engine-version
dependent. The checked-in [UiAutomator2 source fixture](test/fixtures/flutter_android_semantics_source.xml)
was measured on a Pixel 7a running Android 16 and Chrome 150 with Flutter
3.44.8 stable (framework `058e0af2c2`), engine hash
`13ffd72b2f9a5ca4db2a74ea52d5353ec2e8f939` (revision `0cd610717b`). For
`Semantics(identifier: 'allow', label: 'Allow')`, it records:

```text
View    resource-id='PrimaryFooterButtonKey' clickable=false  <- outer wrapper
  Button (no resource-id, no content-desc)   clickable=true   <- tap target
    View resource-id='allow'                 clickable=false  <- Semantics(identifier:)
      View content-desc='Allow'              clickable=false  <- Semantics(label:)
```

One detail is INVARIANT and load-bearing: `Semantics(identifier:)` becomes
Android `resource-id`, not `content-desc` (the label becomes `content-desc`).

**Where the identifier lands is NOT invariant — it varies by device and OS
version.** The Pixel 7a / Android 16 capture above puts the identifier on a
non-interactive node whose clickable `Button` ancestor is anonymous. A Samsung
SM-M225FV (m22) on Android 13 projects the SAME widget differently: the node
carrying the identifier is itself clickable, so there is no wrapper to climb.
Measured live on `RF8RB21P6LN`:

```text
HARDWARE_ASSERT lenny-f0rq flutter_identifier projection=clickable-self via=xpath
```

Do not write selection logic against either tree shape. The two measurements are
recorded here precisely so that nobody hardcodes one of them.

Consequently, the iOS-working `NativeSelector(a11yId: 'allow')` matches nothing
on Android and returns no error. Use the explicit Android selector instead:

```dart
final NativeSelector selector = NativeSelector.flutterIdentifier('allow');
```

It expands to
`//*[@resource-id='allow']/ancestor-or-self::*[@clickable="true"][1]`, which is
robust to BOTH shapes by construction: `ancestor-or-self` climbs to the
actionable `Button` on the Pixel and stops at the identifier node itself on the
m22. That is why the selector needs no per-device branch — the variance is in
the tree, not in the API.
`resolve` intentionally does not auto-retry a missed `a11yId` as this XPath:
doing so would make every legitimate accessibility-id miss silently mean
something else.

## Recovering from platform overlays (backend-direct consumers)

A system overlay can hide a field you have already resolved. The commonest is
Chrome's Touch-To-Fill "Use saved password?" sheet, which appears over any
credential form whose origin has a saved password — so every OAuth/Auth0 login
driven through a Chrome Custom Tab hits it. While it is up, **no write path
works**: Chrome refuses `ACTION_SET_TEXT` *and* swallows injected keystrokes.

`enterText` detects it and throws `NativeException` with
`NativeException.fieldObscuredCode`. It does **not** recover, because at that
seam it holds an already-resolved `NativeTarget` and cannot re-resolve the
handle that dismissal invalidates.

**Recovery is automatic only through the Leonard tool surface** — the
`enter_text` tool owns it, being the layer that holds the selector. If you drive
a `NativeBackend` directly, implement this:

```dart
({String readback, bool masked}) result;
try {
  result = await backend.enterText(target, text);
} on NativeException catch (e) {
  if (e.code != NativeException.fieldObscuredCode) rethrow;
  try {
    // Positively gated inside the backend: it THROWS rather than pressing back
    // when nothing is obstructing, so it cannot navigate a Custom Tab away.
    await backend.press('dismiss_overlay');
  } on NativeException {
    // Keep `e` as the cause — see "preserve the original error" below.
    throw e;
  }
  // Dismissal INVALIDATES the handle — re-resolve, never reuse `target`.
  final NativeTarget? fresh = await backend.resolve(selector, cached);
  if (fresh == null) {
    throw NativeException(
      'element disappeared after obstruction dismissal',
      code: NativeException.elementGoneAfterDismissalCode,
    );
  }
  result = await backend.enterText(fresh, text);
}
```

This mirrors `_EnterTextTool` step for step, including which error survives a
failed dismissal. Four things that are easy to get wrong here, each of which
cost a real debugging round:

- **Branch on `code`, never on the message.** The message is model-facing prose
  and may be reworded; `fieldObscuredCode` is the contract.
- **Re-resolve after dismissing.** Reusing the pre-dismissal handle fails in a
  way that looks exactly like the overlay never went away.
- **Never issue a bare `back` yourself to dismiss.** With no overlay present it
  is plain navigation and will close a Custom Tab. `press('dismiss_overlay')`
  is gated on positive detection; hand-rolled dismissal is not.
- **Preserve the original error when dismissal fails.** That same positive gate
  means `dismiss_overlay` throws `no dismissible platform overlay is present`
  when the overlay has already cleared — a real race, since Chrome dismisses the
  sheet on its own timers and the sheet is once-per-page, not once-per-field. If
  you let that replace the obstruction error, the report inverts exactly in the
  confusing case: you get a message that reads like the recovery machinery is
  broken instead of the actionable cause. The dismissal failure is deliberately
  discarded here rather than surfaced — log it if you need it, but do not report
  it as the outcome.

Note also that `resolve` retries internally — ~10 s per **populated** tier, so
~10 s for an xpath-only selector and ~30 s worst case for one carrying an
a11y-id, a label and an xpath that all miss. An outer retry loop multiplies
against that; see its dartdoc before sizing your own budget.

## Mutation-testing pilot

Mutation score is this pilot's primary test-quality metric: it measures the
share of generated behavior changes detected by assertions. Coverage decides
what is worth running: a mutant no test reaches is reported as uncovered
without being run, which lowers the mutation score and leaves the covered-code
score intact.

The engine is [butcher](https://pub.dev/packages/butcher), which parses with
the analyzer and rewrites the AST. `leonard_flutter` is the one exception: it
stays on `mutation_test` through `tool/run_mutation_flutter.sh` until butcher
grows a runner seam for `flutter test`, and the pilot forks on the package type
so that split needs no flag.

From the workspace root, size the run before spending the full mutation cost:

    ./tool/run_mutation_pilot.sh dry

Dry sizing enumerates the mutants without evaluating one; the count is the
`mutants=` line of `artifacts/mutation/leonard_native/dry/summary.txt`. Then
run the calibration, which repeats dry sizing before the scored phase:

    ./tool/run_mutation_pilot.sh full

The report is `artifacts/mutation/leonard_native/full/mutation-report.json`, a
Stryker JSON document the [Stryker report
viewer](https://microsoft.github.io/mutation-testing-elements/) renders.
`summary.txt` beside it carries the same counts one per line, and
`mutation-report.md` lists the survivors per file.
`tool/verify_mutation_rebaseline.dart` reads that JSON document's per-file map.

If `artifacts/coverage/leonard_native.lcov` exists, the runner hands it over as
routing input; an lcov names no test files, so every covered mutant runs the
whole suite. Passing files — which the nightly does — adds `--test-impact`
instead, which drops the lcov and lets butcher collect coverage itself and run
each mutant against only the test files that reach its line, cheapest first.
The portable entry point installed in any repository is:

    ./tool/leonard/run_mutation.sh full path/to/pure_dart_package \
      --repo-root . --coverage artifacts/coverage/package.lcov

`--rules` is refused: it described the regex engine's semantic rules, and
butcher's mutators are built in. Scope is configured by exclusion instead. The
runner generates a `butcher.yaml` at the package root holding the complement of
the selected files and removes it when the run ends, so a hand-authored one is
never overwritten and a generated one is never committed.

The vended runner at `tool/leonard/run_mutation.sh` supports pure Dart only
and rejects Flutter SDK dependencies. Lenny's compatibility pilot at
`tool/run_mutation_pilot.sh` preserves existing Flutter mutation coverage by
forking Flutter packages to its local `flutter test` path; pure-Dart packages
delegate to the vended runner.

Score gating remains opt-in through `--gate` or `MUTATION_GATE=1`, which
propagates butcher's own exit instead of reporting only. A red suite is not
gated: butcher verifies the baseline before it mutates anything and aborts on a
red one either way.

The deferred `lenny-mab` flake must be cleared before mutation expands to
`leonard_devtools`.
