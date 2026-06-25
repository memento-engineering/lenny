# lenny-qxx.4 — leonard_native m4: Launch Lifecycle (Build Spec)

**Base branch:** `feat/leonard-native` (the bead and m2 spec stack here — do NOT land m4 to `main`).
**Package under change:** `packages/leonard_cli` (extends the existing `up`/`down` launch lifecycle).
**Status of dependencies:** m2 (native host + `AppiumBackend` session) is landed; m3 (`lenny-qxx.3`, agent multi-host attach) **depends on m4** and CONSUMES the handle m4 produces.

---

## 1. Goal & Scope

m4 is **only the launch lifecycle**. Today `leonard_drive up` boots **one** target (Flutter or pure-Dart), scrapes **one** VM-service `ws://…/ws` URI into a `LaunchHandle`, holds it, and tears it down on signal / `down`. The native host (`packages/leonard_native/bin/leonard_native_host.dart`) + `AppiumBackend` session exist and tear down cleanly on signal, but **nothing launches them automatically** — they are run by hand against an operator-booted sim and operator-started Appium.

m4 closes that gap. `leonard_drive up`, when given native flags, must:

1. select the target device (a simulator udid),
2. launch the **Flutter target** on that device and discover its `ws://…/ws` URI,
3. spawn the **leonard_native host** against the **same** device udid + bundle and discover **its** `ws://…/ws` URI,
4. assemble a **grown launch handle** carrying `{flutterWsUri, nativeEndpoint, deviceId}`,
5. **HOLD** both channels, emitting one extended machine-readable ready line,
6. on `down` / signal, tear **both** channels (and any device ownership m4 takes) back down cleanly.

The invariant that makes the two channels watch one screen is **shared device identity**: the **same** sim udid feeds both `flutter run -d <udid>` and the native host's `--udid`, and the **same** bundle (`com.nicospencer.lennyspike`) is what both attach to.

### Explicitly out of scope (do NOT build these here)

- **m3 — agent multi-host attach / fragment merge / namespace routing** (`lenny-qxx.3`). m4 produces the dual-endpoint handle; m3 is the consumer that attaches a `LeonardSession` to both endpoints and routes `core.*` → Flutter, `native.*` → native. m4 must **not** touch `leonard_agent` or the loop. Keep `nativeEndpoint` a first-class, scrapeable `ws://` URI symmetric with `flutterWsUri` — that is the entire m3 interface.
- **m5 — the actual Auth0 drive** (tap Log in → consent → type → sign in → callback resume). m4 only proves both channels come **up** and **down**; it does not authenticate. The live e2e in `native_host_e2e_test.dart` explicitly STOPS before SIGN IN, and m4's e2e mirrors that.
- **Any new agent / brain / model behavior.** `leonard_drive` makes no model calls; it boots, holds, hands off, and tears down.

### 1.1 Levers — thin dev setup & backend swappability (design intent, not new work)

m4 must NOT make Appium a precondition for running lenny. Two properties are load-bearing and the build must preserve them:

- **The native channel is strictly opt-in; the thin path is the default.** `leonard_drive up` with no native flags is byte-for-byte today's single-target behavior, zero Appium (AC1). `leonard_native` stays a leaf package that NOTHING in the core (`leonard_agent`/`leonard_contract`/`leonard_host`/`leonard_flutter`) and NOTHING in `leonard_cli` depends on (AC13 — no runtime dep; the host is a `--native-host` filesystem path). A Flutter-only or pure-Dart dev loop never touches Appium, and `melos run test` is green Appium-free (unit tier on fakes; live e2e self-skips). The dev levers: omit the native flags; don't depend on `leonard_native`; attach-not-own (lenny never installs/manages Appium); `--boot-sim` defaults off.
- **The backend is swappable at two levels — Appium is the FIRST impl, not a commitment.**
  1. *Within `leonard_native`:* the `NativeBackend` seam. `AppiumBackend` is one of N impls (it was chosen only because the spike proved it can drive the OS-level Auth0 web view *outside* the Flutter engine). A `PatrolBackend` / `XcuitestBackend` (xcrun/XCTest/lldb, no Appium) / `PlatformChannelBackend` (in-app method channel, no external server at all) is a drop-in behind the same 9-method interface — `NativeExtension`, the four tools, perception, the host, the contract, and the agent are untouched. This expansion is already scoped as **`lenny-qxx.6`**.
  2. *At this (m4) launch layer:* `--native-host <path>` spawns the host as a binary, not a package import — so an entirely different host (different backend, even non-Dart) that speaks `ext.exploration.*` + prints `LEONARD_HOST_READY` + a `ws://` URI is swappable without m4 changing.

**Deliberate, documented coupling deferred to qxx.6:** while `--native-host` swaps the host *binary*, m4's native-launch *args* (`--appium-server`, `--udid`, `--app`, `--platform`) are Appium-shaped. m4 keeps them as-is (do NOT build a backend-neutral launch abstraction here — there is no second backend yet to validate it against; YAGNI). Generalizing the launch arg surface (e.g. pass-through `--native-arg k=v`, or a host-declares-its-args handshake) lands with the second backend in qxx.6. The cost of deferral is ~5 lines.

---

## 2. Device-Ownership DECISION (the one human-review fork — resolved)

The open question: does `leonard_drive` **own** booting the sim + the Appium session lifecycle, or **attach** to an externally-provisioned device + Appium server?

**DECISION (settled in this spec):**

`leonard_drive` **ATTACHES** to an operator-provisioned **Appium SERVER** and an operator-/CI-booted **simulator**. It **OWNS** only the lenny-side host + session lifecycle. Concretely:

| Concern | Owner |
|---|---|
| Appium server (process at `http://127.0.0.1:4723`) | **Operator** (attach) |
| iOS simulator boot (`xcrun simctl boot <udid>`) | **Operator / CI** (attach) — see note below |
| Launching the Flutter target on `<udid>` (`flutter run -d <udid>`) | **leonard_drive** (own) |
| Building/installing the app bundle | **leonard_drive** (own, via `flutter run`) |
| Spawning + holding the leonard_native host process | **leonard_drive** (own) |
| `AppiumBackend.connect()` / `.close()` W3C session | **leonard_drive** (own, via the held native host) |
| Tearing down both hosts + the WebDriver session | **leonard_drive** (own) |

**Why attach, not own (the rationale, load-bearing):**

1. **m2 already drew this exact line in code.** `NativeBackend.connect()` doc: *"Open the device session against an ALREADY-RUNNING Appium server and an ALREADY-BOOTED simulator. The backend does NOT spawn Appium or boot the sim (that lifecycle is m4)."* `NativeBackend.close()` doc: *"Does NOT stop Appium or shut down the sim."* The native host header repeats it. Reversing this in m4 would contradict a settled milestone and falsify three docstrings.
2. **Sim boot / Appium start are slow, environment-specific** (Xcode / iOS-runtime / driver-doctor) and already operator-owned per the runbook (`docs/design/leonard-native-appium/runbook.md` Step 2 `xcrun simctl boot`, Step 4 `appium --address …`). Pulling them into `leonard_drive` adds heavy `dart:io` + platform branching for marginal value.
3. **Keeps `leonard_drive` CI- and cross-target-friendly.** The same `up` works for an operator-booted sim, a CI-provisioned device, or a real device, with only `--udid`/`--app` changing.

**The single deliberate softening of "attach":** `leonard_drive` MAY optionally **own sim boot** behind an explicit opt-in flag `--boot-sim` (default **OFF**). When set, `up` runs `xcrun simctl boot <udid>` (idempotent — a clear "already booted" is success) BEFORE the Flutter launch, and the grown `shutdown()` runs `xcrun simctl shutdown <udid>` LAST. This is the ONE new ownership m4 is permitted to take; it lives **above** the `NativeBackend` seam (in `launcher.dart` / `leonard_drive`), so the m2 backend docstrings stay true. **The Appium server is never owned** — `up` only *probes* it (`GET <server>/status`) and fails with an actionable error if absent.

> **This `--boot-sim` opt-in default is the ONE human-review fork.** Everything else in this spec is independent of it because both paths attach to the Appium server and own only the session/hosts. If the reviewer wants m4 to default to OWN (boot the sim by default) or to drop sim-boot entirely, flip the `defaultsTo` / delete the flag — a one-line change nothing else depends on.

---

## 3. The Grown Launch Handle

> **§3 framing note (maps reconciliation).** Three of the four design maps describe m4's growth as "grow `LaunchHandle` from one URI to `{flutterWsUri, nativeEndpoint, deviceId}`" (two say "rename `wsUri`→`flutterWsUri`"). That design intent is **REALIZED here as `DualLaunchHandle` wrapping two `LaunchChannel`s** — the per-process `LaunchHandle` primitive is preserved **unchanged**. The divergence from the maps' "rename `wsUri`" is **intentional**, not a miss: `LaunchHandle` is per-process (one `Process`, one runner-aware `shutdown`), so two processes = two channels, and the design fields become the composite's accessors (mapping table below).

The design's "LaunchHandle" **is** the real existing `class LaunchHandle` in `packages/leonard_cli/lib/src/launcher.dart`. Today it holds one URI + one `Process`:

```dart
class LaunchHandle {
  LaunchHandle._(this.wsUri, this.process, this._runner, this._logSubs);
  final Uri wsUri;
  final Process process;
  final TargetRunner _runner;
  final List<StreamSubscription<String>> _logSubs;
  Future<int> get exitCode => process.exitCode;
  Future<void> shutdown({Duration grace = const Duration(seconds: 8)});
}
```

### 3.1 Extract a `LaunchChannel` interface (so the unit tier can inject fakes)

`LaunchHandle` is a concrete `final` class with a private ctor and a real `Process` field, so today there is **no interface a test can fake against**. Extract a minimal abstract interface that captures exactly the three members the composite consumes, and make `LaunchHandle` implement it — a **no behavior change** (it already has `wsUri` / `exitCode` / `shutdown`):

```dart
/// The narrow contract the dual handle consumes from each per-process channel.
/// `LaunchHandle implements LaunchChannel` at runtime; a `FakeLaunchChannel`
/// implements it in unit tests so `launchDualTarget` / `DualLaunchHandle`
/// teardown can be exercised without spawning real processes.
abstract class LaunchChannel {
  Uri get wsUri;
  Future<int> get exitCode;
  Future<void> shutdown({Duration grace});
}

class LaunchHandle implements LaunchChannel { /* ...unchanged... */ }
```

`LaunchHandle.shutdown`'s existing default (`grace = const Duration(seconds: 8)`) stays; the interface declares `shutdown({Duration grace})` (an interface may omit the default — implementers supply it). No other change to `LaunchHandle`.

### 3.2 `DualLaunchHandle` — the composite

A native launch is a **second** `launchTarget` boot (the native host is itself a `dart run --enable-vm-service` program that prints a VM-service URL), so the cleanest growth is a **composite** that holds **two `LaunchChannel`s** plus the shared identity. The fields are typed `LaunchChannel` (NOT concrete `LaunchHandle`) so unit tests can inject `FakeLaunchChannel`s; at **runtime these ARE `LaunchHandle`s**.

```dart
/// A held dual-channel launch: the Flutter target + the native host, both
/// pointed at the SAME device. Produced by [launchDualTarget]; held by
/// `leonard_drive up`; consumed (its two ws URIs) by m3's multi-host attach.
///
/// Holds two [LaunchChannel]s: a [LaunchHandle] for each at runtime, or a
/// FakeLaunchChannel in unit tests (the interface exists only for that seam).
class DualLaunchHandle {
  DualLaunchHandle._(this.flutter, this.native, this.deviceId, this._owned);

  /// @visibleForTesting — build the composite directly from two channels so a
  /// unit test can drive [shutdown] ordering against FakeLaunchChannels
  /// without spawning. Production code uses [launchDualTarget].
  @visibleForTesting
  factory DualLaunchHandle.forTest({
    required LaunchChannel flutter,
    required LaunchChannel native,
    required String deviceId,
    bool owned = false,
  }) => DualLaunchHandle._(flutter, native, deviceId, owned);

  /// The Flutter target channel — `flutter run -d <deviceId>`.
  /// `flutter.wsUri` is the design's `flutterWsUri`.
  final LaunchChannel flutter;

  /// The native channel — the held leonard_native host process.
  /// `native.wsUri` is the design's `nativeEndpoint`.
  final LaunchChannel native;

  /// The shared simulator udid both channels target — the design's `deviceId`
  /// and the shared-identity invariant. Equals `flutter run -d <deviceId>`
  /// AND the native host's `--udid`.
  final String deviceId;

  /// True iff `up` booted the sim itself (--boot-sim); drives sim shutdown.
  final bool _owned;

  Uri get flutterWsUri => flutter.wsUri;   // convenience aliases for the handoff
  Uri get nativeEndpoint => native.wsUri;

  /// Fires when EITHER channel exits (so the holder can tear the other down).
  Future<int> get exitCode => Future.any(<Future<int>>[
        flutter.exitCode,
        native.exitCode,
      ]);

  /// Dependency-reverse teardown (see §5). Serial, idempotent, every leg runs.
  Future<void> shutdown({Duration grace = const Duration(seconds: 8)});
}
```

Design field → real member mapping: `flutterWsUri` = `flutter.wsUri`, `nativeEndpoint` = `native.wsUri`, `deviceId` = `deviceId`. The private ctor `DualLaunchHandle._` is constructed only by the new `launchDualTarget()` in `launcher.dart` (mirroring `LaunchHandle._` / `launchTarget`) and by the `@visibleForTesting` `forTest` factory.

> **Why a composite, not new fields on `LaunchHandle`:** `LaunchHandle` is per-process (one `Process`, one runner-aware `shutdown`). Two processes = two channels. Stuffing a second process into `LaunchHandle` would break its single-runner `shutdown()` semantics. The composite reuses both primitives verbatim and only adds the aggregate teardown + the shared `deviceId`.

---

## 4. `up` Flow (ordered)

All steps live in `_up` (`bin/leonard_drive.dart`) + a new `launchDualTarget()` (`lib/src/launcher.dart`). Reuses the existing `launchTarget` / `buildRunnerInvocation` / `parseVmServiceWsUri` primitives — **no new spawner or scraper** (the native readiness sentinel is a new *parameter* on the existing `launchTarget`, §4.1).

When native flags are absent, `_up` behaves **exactly as today** (single Flutter/dart target). The dual path activates iff **any** of `{--udid, --app, --native-host}` is present (see §6).

**Native path, ordered:**

1. **Validate args (exit 64, before any spawn).** `--target` required; native channel requires ALL of `{--udid, --app, --native-host}` (any one present ⇒ all required; partial ⇒ exit 64 naming the missing flag(s)); `--runner` must be `flutter` (the native dual path pairs a Flutter target with the native host — `--runner dart` + native flags is a hard error); positive `--timeout`; `--app` path must exist on disk; the resolved native-host path must exist on disk (see §6 `--native-host` auto-resolution). On the dual path `-d`/`--device` is **superseded** by `--udid`; passing both with different values → exit 64. Fail-loud, "no dual mode" (mirrors today's `--device` + `--runner dart` rule).
2. **(opt-in) Boot the sim.** If `--boot-sim`: run `xcrun simctl boot <udid>` (treat "current state: Booted" / already-booted as success). Default OFF → assume operator-booted.
3. **Pre-flight probe Appium.** `GET <appium-server>/status` (3s connect, 5s read timeout, like `native_host_e2e_test._appiumReachable`). On failure → exit 1 with an actionable message: `error: Appium not reachable at <server> — start it (operator-provisioned) or pass --appium-server`. This converts the otherwise opaque "native host exited before a VM service URI" into a clear precondition error.
4. **Launch the Flutter target.** `launchTarget(runner: TargetRunner.flutter, entrypoint: <target>, device: <udid>, onLog: stderr.writeln, timeout: <timeout>)`. The `-d <udid>` value is the SHARED `deviceId`. On `TimeoutException` / `StateError` → exit 1; nothing else is booted yet (no compensation needed).
5. **Spawn the native host** against the SAME device, gated on `LEONARD_HOST_READY` (§4.1):
   ```dart
   launchTarget(
     runner: TargetRunner.dart,
     entrypoint: <native-host-path>,
     disableAuthCodes: true,
     extraArgs: <String>['--server', <appium-server>, '--udid', <udid>,
                         '--app', <app>, '--platform', 'ios'],
     readyLine: 'LEONARD_HOST_READY',
     onLog: stderr.writeln,
     timeout: <timeout>,
   )
   ```
   This runs exactly `dart run --enable-vm-service=0 --disable-service-auth-codes <native-host> --server … --udid … --app … --platform ios`, the proven invocation in `native_host_e2e_test.dart`. `parseVmServiceWsUri` scrapes the VM URL the Dart VM prints; the `readyLine` gate (§4.1) makes `launchTarget` return only after the host ALSO prints `LEONARD_HOST_READY` (i.e. after `AppiumBackend.connect()` succeeded).
   **Compensation (BOUNDED):** if this boot throws, the already-booted Flutter channel MUST be torn down before rethrowing/exiting — `launchTarget` kills only *its own* child on failure, so the Flutter boot would otherwise leak. Tear it down with a **bounded grace** so a failed boot never hangs the full ~16s (`q` wait + SIGTERM-grace + SIGKILL-grace) window:
   ```dart
   await flutter.shutdown(grace: const Duration(seconds: 2));
   ```
   Wrap steps 4–5 so a native-boot failure unwinds the Flutter boot.
6. **Map the native-boot failure to a precondition error.** If the host exits before `LEONARD_HOST_READY` (Appium down / sim not booted / `connect()` failed), `launchTarget` throws the §4.1 `StateError`. `up` catches it, tears down the Flutter channel (bounded grace, step 5), and exits 1 with the concrete message:
   `error: native host exited before LEONARD_HOST_READY — is Appium up at <server> and the sim (<udid>) booted?`
7. **Assemble + emit.** Build `DualLaunchHandle._(flutter, native, udid, ownedSim)`. Emit ONE extended JSON line on stdout (extend the existing `vm_service_ready` envelope — see §6 handoff), and write `--uri-file` (§6) / `--pid-file` (the up process's OWN pid).
8. **HOLD.** Same hold machinery as today: a `Completer<int> done`; `tearDown(why)` calls `handle.shutdown()`; subscribe `SIGINT` (always) + `SIGTERM` (best-effort, platform-guarded try/catch); complete when `handle.exitCode` fires (i.e. EITHER child exits). On exit, delete the pid-file and emit `{event:'shutdown'}`.

### 4.1 Native readiness sentinel — `readyLine` on `launchTarget`

`launchTarget` completes on the scraped VM URL, which the native host prints **before** `host.install()` runs `AppiumBackend.connect()` (`leonard_native_host.dart` prints `LEONARD_HOST_READY` only *after* `await host.install()`). So the URL alone does NOT prove the Appium session is live — driving on it would race the session open.

**Mechanism (resolved — the only implementable design):** add an **optional `String? readyLine`** parameter to `launchTarget`. The native leg's stdout/stderr are **single-subscription** and already fully consumed by `launchTarget`'s own `scan()` subscriptions; a post-hoc external `_awaitLine(process, …)` helper would throw "Stream already listened to". Therefore the sentinel MUST be threaded into `launchTarget`'s existing internal `scan()` closure, completing a **second `Completer`** alongside the URI scrape.

New signature:

```dart
Future<LaunchHandle> launchTarget({
  required TargetRunner runner,
  required String entrypoint,
  String? device,
  int vmServicePort = 0,
  bool disableAuthCodes = false,
  List<String> extraArgs = const <String>[],
  String? readyLine,                       // NEW: when non-null, also gate on this literal line
  required void Function(String line) onLog,
  Duration timeout = const Duration(seconds: 180),
});
```

Behavior when `readyLine != null` (single-target callers pass `null` and are unaffected):

- `scan(line)` gains a second branch: when `readyLine != null && line.contains(readyLine!)`, complete a `Completer<void> ready` (guard `!ready.isCompleted`). This reuses the SAME single `scan` already wired to both stdout and stderr — no new subscription.
- `launchTarget` awaits **both** completers under the existing `.timeout(timeout)`: `await wsUri.future.timeout(timeout)` AND, when `readyLine != null`, `await ready.future.timeout(timeout)`. It returns the `LaunchHandle` only after **both** the ws-URI scrape AND `readyLine` are seen.
- The existing exit-before-ready guard (`proc.exitCode.then((code) { if (!wsUri.isCompleted) wsUri.completeError(StateError(...)); })`) is extended to ALSO error the `ready` completer with the **specific** message when `readyLine` is set, so step 6's precondition error is concrete:
  `StateError('native host exited (code $code) before LEONARD_HOST_READY')`.
  (`up` reformats this into the operator-facing message in §4 step 6; the e2e + unit tier assert on the `LEONARD_HOST_READY` token.)
- Same single failure path on timeout/error: cancel both subscriptions, SIGTERM the child, rethrow — already at `launcher.dart`'s `try/catch` around the await.

`parseVmServiceWsUri` and `buildRunnerInvocation` stay **untouched** (pure, already correct for the native host shape).

**Same-device / same-bundle enforcement.** The udid threaded into `flutter run -d <udid>` and the native host `--udid` is **literally the same `String`** (the `deviceId` field) — never derived separately. The bundle (`com.nicospencer.lennyspike`) is implied by `--app <Runner.app>` on the native side and by what `flutter run` installs. **Bundle identity is document-and-trust for m4** — `up` does NOT parse `CFBundleIdentifier`; the enforced invariant is the shared udid (one `String` to both legs). The operator MUST point `--app` at the same app the Flutter target builds; this is a documented requirement, not a checked one. (The existing free-form `-d` flutter device id is REPLACED by `--udid` on the dual path so the two legs can never diverge.)

---

## 5. `down` / Teardown

`down` is **unchanged in contract**: it reads `--pid-file` and `Process.killPid(pid, SIGTERM)` the held `up` process; the up process's signal handler runs `tearDown → handle.shutdown()`. **The single `--pid-file` stays the entire teardown handle** — all new teardown rides on the extended `DualLaunchHandle.shutdown()`. No new `down` flags, no new event types.

`DualLaunchHandle.shutdown()` tears down in **dependency-reverse, strictly serial** order and is idempotent; every leg runs even if a prior leg throws (wrap each in try/catch, swallow on teardown):

```dart
Future<void> shutdown({Duration grace = const Duration(seconds: 8)}) async {
  try { await native.shutdown(grace: grace); } on Object { /* swallow */ }
  try { await flutter.shutdown(grace: grace); } on Object { /* swallow */ }
  if (_owned) {
    try { await _simctlShutdown(deviceId); } on Object { /* swallow */ }
  }
}
```

1. **Native session first.** `await native.shutdown()` — SIGTERM the native host (dart runner). Its `ProcessSignal.sigterm` handler runs `NativeExtension.dispose()` → cancels the watcher → `AppiumBackend.close()` (best-effort `DELETE /session`, then `client.close()`). This releases the WebDriver / WDA session. Escalates SIGTERM → SIGKILL per the existing `LaunchHandle.shutdown()` grace logic.
2. **Flutter target next.** `await flutter.shutdown()` — sends interactive `q` to flutter stdin (graceful quit, which also removes the app from the device), then SIGTERM → SIGKILL escalation. **The serial order is normative:** `native.shutdown()` fully completes (the `DELETE /session` is issued) BEFORE `flutter.shutdown()` begins — the flutter `q` uninstall is safe only AFTER the WDA session is released, which the serial native-first order guarantees (the two channels share the bundle, so uninstalling under a still-settling WDA teardown would otherwise race).
3. **Sim last, only if owned.** If `_owned` (`--boot-sim` was set): `xcrun simctl shutdown <deviceId>` (best-effort). Never touched when attaching to an operator-booted sim. The Appium **server** is never stopped (attach).

**Teardown-in-finally discipline** (the `run.dart` precedent): any consumer that boots via `launchDualTarget` must `await handle.shutdown()` in a `finally`, a no-op when attaching to external URIs. `up`'s hold loop already does this through `tearDown`.

**Stale-holder gotcha (call out in code):** `down` requires the `up` process to be alive with its SIGTERM handler intact. If `up` is gone, `killPid` fails and the WDA session + (if owned) the sim could leak. `AppiumBackend.close()` is already best-effort-on-any-exit (the host's own signal handler covers the common case); the spec only requires that the native host's own SIGTERM handler remains the backstop (it already disposes the extension). **No reaper is in scope for m4.** The un-reaped-child risk is **benign under the attach default** (the operator owns the sim, so nothing lenny created leaks) but becomes a leaked **BOOTED SIM** under `--boot-sim` (operator-visible resource state); if a future milestone defaults `--boot-sim` on, a reaper/guard moves into scope. No code change for m4.

---

## 6. CLI Surface

Extend the `leonard_drive` `ArgParser` in `bin/leonard_drive.dart` (`_parser()`), and the `_up` validation. New/changed options:

| Flag | Applies to | Notes |
|---|---|---|
| `--udid <sim-udid>` | `up` (native dual path) | The SHARED device identity. Feeds BOTH `flutter run -d <udid>` and the native host `--udid`. Part of the native-channel activation trigger. |
| `--app <Runner.app>` | `up` (native) | Path to the built `.app` bundle for `AppiumBackend.app`. Part of the activation trigger. Must exist on disk (exit 64 if not). |
| `--native-host <path>` | `up` (native) | Filesystem path to `leonard_native_host.dart`. Part of the activation trigger. `leonard_cli` does NOT (and must not) depend on `leonard_native`, so the host is a runtime path. When **omitted**, best-effort auto-resolve (see below); must resolve to an existing file or exit 64. |
| `--appium-server <url>` | `up` (native) | Default `http://127.0.0.1:4723`. ATTACH — pre-flight probed, never spawned. |
| `--platform <ios>` | `up` (native) | Default `ios` (Android deferred, mirrors `AppiumBackend`). |
| `--boot-sim` (flag) | `up` (native) | Opt-in: `up` runs `xcrun simctl boot <udid>` and owns sim shutdown. Default OFF (attach to operator-booted sim). The §2 review fork. |

**Dual-mode activation (resolved — implicit, no `--native` flag).** The native channel activates iff **any** of `{--udid, --app, --native-host}` is present. Once activated, **ALL THREE are required**, else exit 64 naming the missing flag(s). There is **no** `--native` toggle flag. This single rule drives the exit-64 cases below and AC3.

**`--native-host` resolution (resolved).** Prefer an explicit `--native-host <path>`. When omitted, **best-effort auto-resolve** the real host relative to the workspace root, mirroring `native_host_e2e_test._hostScript()`'s dual-path resolver: try in order `bin/leonard_native_host.dart`, then `packages/leonard_native/bin/leonard_native_host.dart`, picking the first that exists. If neither the flag nor the auto-resolve finds an existing file → exit 64 (`error: native host not found — pass --native-host <path>`).

**"No dual mode" hard errors (all exit 64, before any spawn):**

- Any native flag (`--udid`/`--app`/`--native-host`/`--appium-server`/`--platform`/`--boot-sim`) with `--runner dart` → hard error (the native dual path pairs a Flutter target with the native host; a pure-Dart Flutter-less target has no shared screen).
- The dual path with only some of `{--udid, --app, --native-host}` (after auto-resolution) → hard error naming the missing flag(s) (partial native config is a mistake, not a silent single-target fallback).
- On the dual path, the existing free-form `--device`/`-d` is **superseded** by `--udid`. Passing both `-d X` and `--udid Y` with `X != Y` → hard error (prevents the divergent-screen failure mode). On the dual path require `--udid` and forbid a conflicting `-d`.
- Single-target path (no native flags) keeps today's behavior and validation verbatim.

**Handoff envelope (extend, do not add new event types).** Today `up` emits one line `{event:"vm_service_ready", ws_uri, runner, pid}`. On the dual path, emit ONE extended line carrying both endpoints + the shared device:

```json
{
  "event": "vm_service_ready",
  "ws_uri": "ws://127.0.0.1:PORT/ws",        // = flutter_ws_uri (back-compat: ws_uri stays the Flutter/primary channel)
  "flutter_ws_uri": "ws://127.0.0.1:PORT/ws",
  "native_endpoint": "ws://127.0.0.1:PORT2/ws",
  "device_id": "<sim-udid>",
  "runner": "flutter",
  "pid": 12345                                // the up process's own pid
}
```

**`--uri-file` on the dual path (resolved).** Write **BOTH** URIs, newline-separated, **FLUTTER FIRST**:

```
<flutter_ws_uri>
<native_endpoint>
```

i.e. `'${flutterWsUri}\n${nativeEndpoint}\n'`. **Line 1 is byte-compatible** with today's single-target `'${wsUri}\n'`, so a consumer that reads only line 1 still gets the primary/Flutter URI. `--pid-file` is unchanged (the up process's own pid). The machine-readable JSON stdout line is the primary handoff; `--uri-file` is the convenience fallback.

**`cli_args.dart` mirror — do NOT extend for m4.** The parallel `leonard_cli --launch` surface in `cli_args.dart` stays single-target for m4 (the autonomous native loop is m3/m5 territory, not m4 scope). The native dual path lives in `leonard_drive up` only, since the external-brain (drive) path is what m3 attaches to. (If a native mirror is ever added it MUST stay `dart:io`-free — no `launcher` imports; map at the `run.dart` io boundary — mirror `LaunchRunner` not `TargetRunner`, and follow the same implicit-activation hard-error idiom.)

---

## 7. Acceptance Criteria

Each is independently verifiable; the HOW is named. Tiers (§9): T1 = unit/wiring (default `melos run test`); T2 = live dogfood (hardware-gated, self-skips).

1. **Single-target path is unchanged.** `leonard_drive up --runner dart -t <fixture>` and `--runner flutter -d <dev> -t <entry>` behave exactly as today (one `ws_uri`, hold, `down`). *Check (T1):* existing `launch_e2e_test.dart` + `leonard_drive_up_test.dart` pass unmodified.
2. **`DualLaunchHandle` carries `{flutter.wsUri, native.wsUri, deviceId}`.** *Check (T1, `dual_launch_wiring_test.dart`):* build via `DualLaunchHandle.forTest` from two `FakeLaunchChannel`s; assert `flutter.wsUri` / `native.wsUri` / `flutterWsUri` / `nativeEndpoint` expose the two ws URIs and `deviceId` is the shared value, and that the wired-up `launchDualTarget` (with an injected `spawn`, AC6/AC10) passes the same `udid` to both the Flutter `device` and the native `--udid` extraArg.
3. **Native flags missing/partial → exit 64 before any spawn.** *Check (T1, `leonard_drive_up_test.dart`):* native flags + `--runner dart`; `--udid` without `--app`; `--udid` + `--app` without a resolvable `--native-host`; nonexistent `--app` path; nonexistent `--native-host` path; `-d X` + `--udid Y` (Y≠X). Each asserts exit 64 and a message naming the offending flag, with **no** subprocess boot.
4. **`up` builds the native host invocation correctly.** *Check (T1, pure unit on `buildRunnerInvocation`):*
   ```dart
   buildRunnerInvocation(
     runner: TargetRunner.dart,
     entrypoint: nativeHost,
     disableAuthCodes: true,
     extraArgs: <String>['--server', u, '--udid', ud, '--app', a, '--platform', 'ios'],
   ).args
   == <String>['run', '--enable-vm-service=0', '--disable-service-auth-codes',
               nativeHost, '--server', u, '--udid', ud, '--app', a, '--platform', 'ios']
   ```
   (Pure function only — no spawn; `launchDualTarget` is covered by AC6/AC10 via the spawn seam.)
5. **Appium pre-flight gives an actionable error when absent.** *Check (T1):* point `--appium-server` at a dead port and assert exit 1 with a message naming Appium + the server URL (NOT a raw `StateError`/`NativeException`).
6. **Compensation: a native-boot failure tears down the already-booted Flutter channel (bounded).** *Check (T1, `dual_launch_wiring_test.dart`):* inject a `spawn` into `launchDualTarget` whose Flutter call returns a `FakeLaunchChannel` and whose native call throws after the Flutter leg succeeds; assert the Flutter channel's `shutdown(grace: Duration(seconds: 2))` was recorded (no leaked Flutter process) before `launchDualTarget` rethrows. The `FakeLaunchChannel.shutdown()` is a recorded no-op, so this asserts the call **without** exercising the real `q`/SIGTERM path.
7. **Extended ready envelope + `--uri-file` are correct.** *Check (T2):* the dual e2e parses one `vm_service_ready` line and asserts it contains `flutter_ws_uri`, `native_endpoint` (both valid `ws://`), and `device_id` == the supplied udid; and asserts `--uri-file` holds two lines, **flutter first** (`<flutter_ws_uri>\n<native_endpoint>\n`).
8. **Native readiness is gated on `LEONARD_HOST_READY`.** *Check (T2):* the native channel is driven only after the host prints `LEONARD_HOST_READY` — the dual e2e does a single-channel `leonard_drive`-style `tools`/`observe` against `native_endpoint` and sees the `native` namespace/fragment. **m3 boundary:** single-host handshake only — it must NOT attach a second session to `flutter_ws_uri`, NOT merge fragments, NOT route by namespace (all m3). It reuses the existing single-channel CLI path against `native_endpoint`, not a bespoke dual-attach harness.
9. **`down` tears BOTH channels down cleanly via one `--pid-file`.** *Check (T2):* run `down --pid-file P`; assert `up` exits 0, emits `{event:"shutdown"}`, and BOTH child processes are gone (poll their pids). The Appium session is released (best-effort `DELETE /session` issued via the host's dispose).
10. **Teardown order is dependency-reverse and serial.** *Check (T1, `dual_launch_wiring_test.dart`):* `DualLaunchHandle.forTest` with two recording `FakeLaunchChannel`s; assert `native.shutdown()` fully resolves before `flutter.shutdown()` is called, and (when `owned: true`) the `simctl shutdown` hook runs last; assert all legs still run when one throws.
11. **`--boot-sim` owns sim lifecycle; default attaches.** *Check (T1):* `DualLaunchHandle.forTest(owned: true)` schedules the `simctl shutdown` hook on teardown; `owned: false` leaves the sim untouched. (The `simctl` calls themselves are stubbed/guarded in unit tests; only T2 exercises real `simctl`, behind the same env gate.)
12. **`nativeEndpoint` is symmetric with `flutterWsUri` (m3-ready).** *Check (T2):* `native_endpoint` is a `ws://…/ws` URI a `LeonardSession.connect()` accepts; the dual e2e attaches a single driver to `native_endpoint` and handshakes the `native` namespace, proving m3's input is well-formed. **m3 boundary:** single-host handshake only; dual-attach / merge / route is m3 — do NOT also attach to `flutter_ws_uri`.
13. **`feat/leonard-native` base; no `leonard_native` runtime dep added.** *Check (T1):* `packages/leonard_cli/pubspec.yaml` gains no `dependencies: leonard_native` entry; the native host is referenced only as a runtime filesystem path (`--native-host`). `melos run analyze` clean.

---

## 8. Implementation Plan (file-by-file, ordered)

All under `packages/leonard_cli`, on `feat/leonard-native`.

1. **`lib/src/launcher.dart`** — extract the interface, add the dual primitive, add the readiness sentinel:
   - **Extract** `abstract class LaunchChannel { Uri get wsUri; Future<int> get exitCode; Future<void> shutdown({Duration grace}); }` and declare `class LaunchHandle implements LaunchChannel` (no behavior change — it already has all three).
   - **Add `String? readyLine`** to `launchTarget` (§4.1): thread it into the existing internal `scan()` (complete a second `Completer<void> ready` on the literal line); await BOTH completers under the existing `.timeout`; extend the exit-before-ready guard to error `ready` with `StateError('native host exited (code $code) before LEONARD_HOST_READY')`. `parseVmServiceWsUri` / `buildRunnerInvocation` untouched.
   - **Add `class DualLaunchHandle`** (§3.2): private ctor + `@visibleForTesting` `forTest` factory; the two `LaunchChannel` fields, `deviceId`, `_owned`; `exitCode = Future.any([flutter.exitCode, native.exitCode])`; the serial dependency-reverse `shutdown()` (§5).
   - **Add the spawner seam + `launchDualTarget`:**
     ```dart
     typedef TargetSpawner = Future<LaunchChannel> Function({
       required TargetRunner runner,
       required String entrypoint,
       String? device,
       bool disableAuthCodes,
       List<String> extraArgs,
       String? readyLine,
       required void Function(String) onLog,
       required Duration timeout,
     });

     Future<DualLaunchHandle> launchDualTarget({
       required String flutterEntrypoint,
       required String udid,
       required String app,
       required String nativeHostPath,
       Uri? appiumServer,
       String platform = 'ios',
       bool bootSim = false,
       required void Function(String) onLog,
       Duration timeout = const Duration(seconds: 180),
       @visibleForTesting TargetSpawner spawn = launchTarget,
     });
     ```
     `spawn` defaults to `launchTarget` (whose signature is assignment-compatible with `TargetSpawner`). Internally: (opt) `_bootSim(udid)`, `_probeAppium(server)`, `final LaunchChannel flutter = await spawn(runner: flutter, entrypoint: flutterEntrypoint, device: udid, …)`, then under a compensation wrapper `final LaunchChannel native = await spawn(runner: dart, entrypoint: nativeHostPath, disableAuthCodes: true, extraArgs: [...], readyLine: 'LEONARD_HOST_READY', …)`; on native throw `await flutter.shutdown(grace: const Duration(seconds: 2))` then rethrow; finally `DualLaunchHandle._(flutter, native, udid, bootSim)`. The wiring test injects a `spawn` returning canned/throwing `FakeLaunchChannel`s.
   - **Add private io helpers** here (this file already owns `dart:io`): `_bootSim`/`_simctlShutdown` (`xcrun simctl boot|shutdown`, idempotent / best-effort) and `_probeAppium` (`GET /status`, 3s/5s). Keep `leonard_agent` io-free — none of this leaks upward.
2. **`bin/leonard_drive.dart`** — extend the CLI:
   - `_parser()`: add `--udid`, `--app`, `--appium-server`, `--platform`, `--native-host`, `--boot-sim`. Update `_usage()`.
   - `_up()`: detect the dual path (any of `{--udid,--app,--native-host}` present); auto-resolve `--native-host` when omitted; run the §6 "no dual mode" exit-64 validations (before any spawn); call `launchDualTarget` instead of `launchTarget`; map its precondition `StateError` to the §4-step-6 message + exit 1; emit the extended `vm_service_ready` envelope; write the two-line `--uri-file`; hold on the composite's `exitCode`; `tearDown → handle.shutdown()`. Keep the single-target branch verbatim.
   - `_down()` and `_emit()` unchanged.
3. **`test/leonard_drive_up_test.dart`** — add the exit-64 / exit-1 smoke cases from AC3, AC5 (dead-port Appium), following the existing fast-fail-before-spawn pattern.
4. **`test/dual_launch_wiring_test.dart`** (new) — the stubbed-launcher wiring tier (AC2, AC6, AC10, AC11) via the injected `spawn` + `DualLaunchHandle.forTest` with `FakeLaunchChannel`s. **NOT** `*_e2e_test.dart` (test-taxonomy rule: a stubbed boot is unit/wiring).
5. **`test/launcher_test.dart`** — add the pure AC4 `buildRunnerInvocation` native-vector assertion (and re-assert `parseVmServiceWsUri` on the native host's URL line if not already covered).
6. **`test/launch_dual_e2e_test.dart`** (new) — the live, hardware-gated dual e2e (§9 Tier 2), modeled on `launch_e2e_test.dart` + `native_host_e2e_test.dart`.

**Implementation note (load-bearing): no `leonard_native` dependency.** `leonard_cli`'s `pubspec.yaml` does NOT depend on `leonard_native` (and `leonard_host` is only a `dev_dependency`). m4 must NOT add a runtime dep on `leonard_native` — the native host is referenced as a **filesystem path** via `--native-host` (explicit or auto-resolved), spawned through the generic `TargetRunner.dart` runner. This keeps `leonard_cli` decoupled from the native package's transitive deps. The e2e points `--native-host` at the real `packages/leonard_native/bin/leonard_native_host.dart` resolved relative to the workspace.

---

## 9. Validation Plan

Exactly **two tiers**, mirroring the package convention and the **test-taxonomy house rule** (a test that stubs/fakes the external boot is a **unit/wiring** test, NOT e2e; never name a stubbed-boot file `*_e2e_test.dart`). There is **no** device-free "live dual-boot" tier: `launchDualTarget` is hard-gated to `--runner flutter`, which needs a real device, so device-free dual-boot/dual-teardown coverage comes from the **stubbed-launcher wiring test** (`dual_launch_wiring_test.dart`, injected `FakeLaunchChannel`s) — not a real two-host boot.

### Tier 1 — UNIT / wiring (stubbed boot; runs in default `melos run test`)

- **Pure invocation + URI scrape** (`launcher_test.dart`): assert the native leg's arg vector (AC4) via `buildRunnerInvocation`; assert `parseVmServiceWsUri` scrapes the native host's `dart run` URL line (re-assert for the native shape).
- **Arg validation** (`leonard_drive_up_test.dart`): the AC3 exit-64 table + AC5 dead-port exit-1 — all fast-fail BEFORE any spawn (boots nothing), exactly like the existing cases.
- **Lifecycle wiring with a STUBBED launcher** (`dual_launch_wiring_test.dart`; AC2, AC6, AC10, AC11): inject `spawn` into `launchDualTarget` (and use `DualLaunchHandle.forTest`) so a unit test can, without real processes: force native-leg failure → assert Flutter `shutdown(grace: 2s)` ran (AC6); assert teardown order native→flutter→(sim) and that all legs run when one throws (AC10); assert `bootSim`/`owned: true` toggles the `simctl shutdown` hook (AC11); assert the composite exposes both ws URIs + the shared `deviceId` (AC2). `FakeLaunchChannel` implements `LaunchChannel` and records its `shutdown` calls (a no-op — no real `q`/SIGTERM).

### Tier 2 — LIVE dogfood dual e2e (hardware-gated, self-skips)

`test/launch_dual_e2e_test.dart`, modeled on `native_host_e2e_test.dart`'s gate (**no new tag** — the house rule):

- **Sync env gate** at `main()`-time: require `LEONARD_NATIVE_SIM_UDID`, `LEONARD_NATIVE_APP` (+ a resolvable `--native-host` and a Flutter entrypoint/device); `markTestSkipped` + return when absent (env check is synchronous).
- **Async reachability probe INSIDE the test body**: `_appiumReachable(server)` via `GET /status` (3s/5s timeouts) → `markTestSkipped` when Appium is down. (An HTTP probe in a sync `main()`-time gate would `sleep`-deadlock the isolate and always skip.)
- **Drive shape:** run `leonard_drive up --runner flutter --udid <udid> --app <app> --native-host <path> --appium-server <server> -t <flutter-entry> --pid-file P --uri-file F`; parse the extended `vm_service_ready` line; assert `flutter_ws_uri` + `native_endpoint` + `device_id`; assert `--uri-file` has both lines flutter-first (AC7); do a **single-channel** `tools`/`observe` against `native_endpoint` and assert the `native` namespace/fragment is present (proves the Appium session is live, gated on `LEONARD_HOST_READY`; AC8/AC12 m3 boundary — do NOT also attach to `flutter_ws_uri`, merge, or route); run `down --pid-file P`; assert clean `up` exit + `{event:"shutdown"}` + both children gone. **STOP before SIGN IN** (m5 owns auth).
- Drain BOTH stdout and stderr of every spawned process (full-pipe gotcha). Teardown in `finally` with SIGKILL escalation + temp-dir cleanup.
- Reuse `_findPackageRoot()` / `_hostScript()`-style helpers so the test works from repo root or package dir.

**Quality gates before handoff:** `melos run analyze`, `melos run test`, `melos run format`. The hardware tier self-skips locally (no sim/Appium), so the default gate stays green for everyone. Land to `feat/leonard-native` only.

---

## Key constraints / gotchas the builder must respect

- **`leonard_cli` must NOT gain a runtime dep on `leonard_native`** — native host is a `--native-host` filesystem path (explicit or auto-resolved) spawned via `TargetRunner.dart`.
- **`launchTarget` completes on the scraped VM URL, which the native host prints BEFORE `AppiumBackend.connect()`.** Gate native readiness with `readyLine: 'LEONARD_HOST_READY'` (§4.1) or you may drive before the device session is open. The sentinel MUST live inside `launchTarget`'s own `scan()` — an external `_awaitLine` would throw "Stream already listened to" (the process stdout/stderr are single-subscription, already consumed).
- **`--enable-vm-service=0` = random free port** (not disabled); the port is unknown until scraped — never hardcode it.
- **Native host arg parsing is naive `--key value` pairs** (no `=` form, no bare flags). Pass space-separated `--udid <v> --app <v> --server <v> --platform ios`.
- **`buildRunnerInvocation` throws `ArgumentError` if `device` is set with `TargetRunner.dart`** — the native host has no `device`; the udid goes in `extraArgs`, never as the launcher `device`.
- **Compensation is BOUNDED:** `launchTarget` kills only its OWN child on failure; on a native-boot failure after a successful Flutter boot, tear the Flutter channel down with `flutter.shutdown(grace: const Duration(seconds: 2))` so a failed boot never hangs the ~16s default-grace window.
- **Teardown is serial + native-first:** the flutter `q` uninstall is safe only after the WDA session is released; `await native.shutdown(); await flutter.shutdown();`.
- **SIGTERM watching is platform-guarded** (try/catch around `ProcessSignal.sigterm.watch()`); SIGINT + target-exit are the always-present hold triggers.
- **`appium:noReset:true`** means the host attaches to / reuses the installed app — app-state hygiene is m4's lifecycle concern, not the host's.
- **The shared udid is one `String`**, threaded to both legs — never derive the flutter `-d` device and the native `--udid` separately (divergent screens is the worst, silent failure).
- **Bundle identity is document-and-trust** for m4 — no `CFBundleIdentifier` parse; the shared udid is the enforced invariant.
