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

Note also that `resolve` retries internally (~10 s per tier, up to three tiers),
so an outer retry loop multiplies against it — see its dartdoc before sizing
your own budget.

## Mutation-testing pilot

Mutation score is this pilot's primary test-quality metric: it measures the
share of generated behavior changes detected by assertions. Line coverage is
used only to skip instrumented lines with zero hits.

From the workspace root, size the run before spending the full mutation cost:

    ./tool/run_mutation_pilot.sh dry

The measured mutant count is recorded in
`artifacts/mutation/leonard_native/dry/console.txt`. Then run the calibration:

    ./tool/run_mutation_pilot.sh full

If `artifacts/coverage/leonard_native.lcov` exists, the runner supplies a
package-relative copy to `mutation_test`; if it is absent, all candidate lines
remain eligible. The human report is
`artifacts/mutation/leonard_native/full/mutation-test-report.html`. The stable
machine-readable score and survivor data are in
`artifacts/mutation/leonard_native/full/mutation-test-report.xml`; JUnit,
XUnit, and Markdown reports are emitted beside it.

This pilot is informational. It defines no score threshold and is not a pull
request gate. Future pull-request experiments may pass changed production Dart
files as positional inputs, while a fuller sweep rotates separately. Parsing
the XML into the external `tg-5drf.2` ledger projection is owned by that metrics
work and is outside this pilot.

`leonard_native` is pure Dart. An arbitrary test command can be configured in
XML, but `flutter test` compatibility has not been verified, so this result
does not establish mutation testing for Flutter packages. The deferred
`lenny-mab` flake is outside this package and does not corrupt this baseline;
it must be cleared before mutation expands to `leonard_devtools`.
