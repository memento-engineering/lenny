# lenny-qxx.2 — leonard_native (m2): standalone native host + NativeBackend seam + AppiumBackend

> Base branch: **`feat/leonard-native`** (NOT `main`). iOS-first; Android (UiAutomator2) deferred. Do not land to `main`; stack on the feature branch.
>
> Ground truth this spec mirrors: `packages/leonard_tmux/*` (watcher triad: `tmux_extension.dart`, `tmux_observation.dart`, `tmux_perception.dart` + `tmux_extension_test.dart`/`host_e2e_test.dart`), `packages/leonard_contract/lib/src/{extension,perception_extension,types}.dart` (contracts), `packages/leonard_host/lib/src/exploration_host.dart` (host, reused unchanged), `packages/leonard_flutter/lib/src/semantics/semantics_capture.dart` (`_Rec`/`toJson`, the record shape — **bounded edit in this milestone**, see §1.1), the proven spike recipe `~/lenny-spike/RESULTS.md` (GREEN 2026-06-20), and the de-risk skeleton `docs/design/leonard-native-appium/backend_skeleton.dart` + `spec.md`.

---

## 1. Goal & scope

**Goal.** Ship a new pure-Dart package `leonard_native` that lets the existing, target-agnostic Leonard driver (`leonard_agent`/`leonard_cli`/`leonard_drive`) perceive and drive a **native mobile app** (iOS first) over the unchanged `ext.exploration.*` surface — by running `ExplorationHost` with ONE new `NativeExtension` whose observation source is the **OS accessibility tree** (via Appium/XCUITest) instead of a widget tree or a tmux server.

This is the direct native analogue of `leonard_tmux`: `NativeExtension` = `TmuxExtension`, `NativeSnapshot` = `TmuxObservation`, `NativePerception` = `TmuxPerception`, `NativeBackend` = the `TmuxClient`/`PollObservationSource` seam, `AppiumBackend` = `ProcessTmuxExecutor` (the concrete I/O behind the seam).

**In scope (m2):**
- The `leonard_native` package: `NativeExtension` (`LeonardExtension with PerceptionExtension`), the immutable `NativeSnapshot`/`NativeNode` snapshot types, `NativePerception`, the `NativeBackend` seam interface, the first concrete impl `AppiumBackend` (W3C WebDriver → a local Appium server running xcuitest), a reusable `FakeNativeBackend` shipped alongside the seam, and a `bin/` VM-service host entrypoint (`bin/leonard_native_host.dart`).
- Four tools: `native.tap`, `native.enter_text`, `native.press`, `native.swipe`.
- The selector chain (a11y-id → label → XPath → rect-center), with the **XPath fallback load-bearing** (Auth0 fields can be anonymous + positional).
- iOS edge cases reproduced from the spike: the `ASWebAuthenticationSession` consent popup accepted via the W3C alert endpoint (`POST /session/{id}/alert/accept`), and per-platform keyboard dismiss (iOS "Done" / Android back).
- A **single canonical cross-host perceived-node record schema** (§1.1) — emitted identically by the native fragment AND the Flutter semantics fragment. Achieving this requires a **bounded edit** to `packages/leonard_flutter/lib/src/semantics/semantics_capture.dart` (add a first-class `value` field), described in §1.1 and §3.4.
- Unit tests against `FakeNativeBackend`; an env-gated live dogfood e2e that self-skips when Appium/a simulator is absent.

**Out of scope (explicitly deferred):**
- **Android / UiAutomator2** drive — the seam keeps per-platform branching behind the backend so Android is purely additive later. The Android keyboard-dismiss / selector branch exists structurally but is not validated live in m2.
- **m3 multi-host attach** (driving Flutter + native simultaneously). m2 ships only the host + seam + first backend; it deliberately makes the native and Flutter record schemas identical (§1.1) so m3 has nothing to harmonize.
- **m4 launch lifecycle** (boot/teardown of the target under the autonomous loop). The bin entrypoint stays the tmux-style "construct → install → wait on signal" shape; it does NOT manage the Appium server or simulator lifecycle, and m2 does NO launcher wiring.
- **m5 full Auth0 round-trip** (completing SIGN IN, the callback return, resume-on-Flutter). m2's e2e deliberately STOPS before SIGN IN: it proves only host-boots-and-drives + masked-readback, NOT authentication.
- Real-device iOS (sim ≠ device noted; not needed for m2).
- Any change to `leonard_contract`, `leonard_host`, or the `ext.exploration.*` wire surface. m2 adds NO new contract members; those packages are byte-unchanged (§6 AC15).

### 1.1 Decision: one canonical cross-host record schema ("uniform now")

There is ONE perceived-node record schema, emitted byte-for-byte identically by both the native fragment and the Flutter semantics fragment:

```
{ id:int, role:String, rect:[l,t,r,b] ints }   // always present
  label?:String                                 // omitted when null/empty
  value?:String                                 // omitted when null/empty
  state?:List<String>                           // omitted when empty
  actions?:List<String>                          // omitted when empty
  scroll?:Map                                    // omitted when null
```

Canonical key order in serialization: `id, role, rect, label?, value?, state?, actions?, scroll?`.

This is a settled decision, not an open question. Two consequences:

1. **Bounded Flutter change (in m2 scope).** The live Flutter `_Rec` emits `{id, role, rect, label?, state?, actions?, scroll?}` — it has **no `value` key**. m2 adds a first-class `value` field to `_Rec` in `semantics_capture.dart`, sourced from `SemanticsData.value` (already available alongside `d.label`), emitted in `toJson` as `if (value.isNotEmpty) m['value'] = value;` placed **between the `label` and `state` emits** to match the canonical key order. The doc comment (§3.4) is updated to list `value?`, and the pinned `semantics_capture_test.dart` is updated to (a) admit `value` in its schema allow-set and (b) positively assert `value` on a node that carries one (a `TextField` with text, or a `Slider`). **This is the ONLY change to `leonard_flutter`.** `leonard_contract`, `leonard_host`, and the `ext.exploration.*` wire surface stay byte-unchanged.

2. **Native record type mirrors the canonical schema EXACTLY** (same fields, same omit-when-empty, same key order). In m2 the iOS `AppiumBackend` populates `id/role/rect/label/value/actions`; it leaves `state`/`scroll` empty (so they are omitted). The `NativeNode` type still **carries** `state` and `scroll` so its schema is identical to Flutter's and a future backend can fill them. (Optionally map XCUITest `enabled`/`selected` → `state` if trivial; not required for m2.)

Because both hosts now emit the same schema, there is no cross-host divergence to reconcile downstream — **no follow-up "harmonize" bead is needed**. (This resolves the parked value-vs-state question and the AC5 false-parity finding.)

---

## 2. Package layout

New package `packages/leonard_native/`, mirroring `packages/leonard_tmux/` 1:1:

```
packages/leonard_native/
  pubspec.yaml                         # see §2.1
  analysis_options.yaml                # copy leonard_tmux's verbatim
  CHANGELOG.md                         # "## 0.1.0 — initial native host"
  README.md                            # short: what it is, how to run the host
  lib/
    leonard_native.dart                # barrel — exports (see §2.2)
    src/
      native_extension.dart            # NativeExtension (LeonardExtension w/ PerceptionExtension) + 4 private tool classes + selector resolver
      native_snapshot.dart             # @immutable NativeSnapshot + NativeNode (the canonical-schema record carrier)
      native_perception.dart           # NativePerception extends StatelessPerception -> Node/Field Seed
      native_backend.dart              # abstract NativeBackend seam + NativeSelector / NativeTarget / NativeSwipe param types + NativeException
      appium_backend.dart              # AppiumBackend implements NativeBackend (W3C WebDriver over http; XCUITest XML parser)
      fake_native_backend.dart         # FakeNativeBackend implements NativeBackend (records calls, scriptable Stream<NativeSnapshot>) — SHIPPED in lib/, not test/
  bin/
    leonard_native_host.dart           # standalone VM-service host main() (clone of example/tmux_vm_host.dart, in bin/)
  test/
    native_extension_test.dart         # UNIT: watcher arc + buildPerception shape + tool dispatch + selector chain + structured errors + watch resilience (FakeNativeBackend)
    native_host_test.dart              # UNIT: ExplorationHost(extensions:[NativeExtension(fake)]) wire shape (handshake/observation/invoke)
    appium_xml_parser_test.dart        # UNIT: /source XCUITest-XML -> List<NativeNode> parser + xpath synthesis, against a checked-in fixture (§5.3)
    fixtures/
      auth0_source.xml                 # checked-in XML fixture derived from ~/lenny-spike/spike_source.xml (the Auth0 login page subtree)
    native_host_e2e_test.dart          # LIVE e2e: real Appium + booted iOS sim; self-skips when absent; @Timeout
```

> **Note on `bin/` vs `example/`.** tmux puts its host runner in `example/tmux_vm_host.dart`. For native, place it in `bin/leonard_native_host.dart`: `bin/` gives a stable, conventional `dart run` entrypoint. A later launcher (m4) can target it without moving the file. m2 itself does NO launcher wiring, and the bin entrypoint does NOT manage the Appium/sim lifecycle (§1, §4.4). The e2e test's `_hostScript()` helper resolves it from both `bin/leonard_native_host.dart` and `packages/leonard_native/bin/leonard_native_host.dart` (cwd differs by invocation, exactly as the tmux e2e does).

Register the package in the root workspace (`pubspec.yaml` workspace list and Melos package globs) the same way `leonard_tmux` is registered — no new Melos scripts are required (it runs under the existing `melos run test`/`analyze`/`format`).

### 2.1 pubspec.yaml

Mirror `leonard_tmux/pubspec.yaml`, swapping `genesis_tmux` for `http` + `xml`:

```yaml
name: leonard_native
description: >-
  A pure-Dart Leonard contract extension that perceives and drives a native
  mobile app over the OS accessibility tree (via Appium/XCUITest): a stateful,
  self-watching extension projecting the a11y tree into a genesis_perception
  tree and exposing tap / enter_text / press / swipe tools.
version: 0.1.0
repository: https://github.com/memento-engineering/lenny
resolution: workspace

environment:
  sdk: ^3.11.0

dependencies:
  genesis_perception: ^0.1.2
  leonard_contract: ^0.1.0
  http: ^1.2.0          # AppiumBackend W3C WebDriver client (replaces genesis_tmux)
  xml: ^6.5.0           # XCUITest /source XML parse -> List<NativeNode> (§5.3)
  meta: ^1.16.0

dev_dependencies:
  leonard_agent: ^0.1.0   # e2e LeonardSession driver
  leonard_host: ^0.1.0    # ExplorationHost for the host + wire-shape tests and bin/
  lints: ^5.1.0
  test: ^1.25.0
```

> `leonard_host` is a **dev_dependency** (tmux precedent): the library itself only depends on `leonard_contract` + `genesis_perception` (+ `http`/`xml` for the Appium impl); only the host runner (`bin/`) and the host/e2e tests need `ExplorationHost`. Keep this layering — it preserves the "extension is host-agnostic" boundary.
>
> `xml: ^6.5.0` is a NEW dependency for this repo (no existing pubspec pulls it). It backs the §5.3 parser only — the seam, extension, perception, and fake do not touch it.

### 2.2 Barrel (`lib/leonard_native.dart`)

```dart
export 'src/native_extension.dart' show NativeExtension;
export 'src/native_snapshot.dart' show NativeSnapshot, NativeNode;
export 'src/native_perception.dart' show NativePerception;
export 'src/native_backend.dart'
    show NativeBackend, NativeSelector, NativeTarget, NativeSwipe, NativeException;
export 'src/appium_backend.dart' show AppiumBackend;
export 'src/fake_native_backend.dart' show FakeNativeBackend;
```

---

## 3. The NativeBackend seam

The seam is the I/O boundary that keeps `buildPerception()` synchronous (ADR-0006): **all** device latency (WebDriver round-trips, a11y-tree polling) lives behind it. The extension never touches the device directly. `AppiumBackend` is the first impl; `FakeNativeBackend` is the test impl; a later `UiAutomator2Backend` is purely additive.

### 3.1 `native_backend.dart`

```dart
/// Resolved target of a native action — what the selector chain produced.
/// `elementId` is the backend's W3C element handle when one resolved
/// (a11y-id / label / xpath tier); when only rect-center resolved, elementId
/// is null and the backend taps `point`.
@immutable
class NativeTarget {
  const NativeTarget({this.elementId, this.point, required this.via});
  final String? elementId;          // W3C element-6066-... handle, or null
  final ({int x, int y})? point;    // rect-center fallback coordinate, or null
  final String via;                 // 'a11y-id' | 'label' | 'xpath' | 'rect-center'
}

/// A selector spec carrying the raw tool args for the resolution chain.
@immutable
class NativeSelector {
  const NativeSelector({this.a11yId, this.label, this.xpath, this.rect});
  final String? a11yId;      // tier 1
  final String? label;       // tier 2 (matched against node.label)
  final String? xpath;       // tier 3 (load-bearing for anonymous Auth0 fields)
  final List<int>? rect;     // tier 4: [l,t,r,b]; tap at center ((l+r)/2,(t+b)/2)
}

@immutable
class NativeSwipe {
  const NativeSwipe({
    required this.fromX, required this.fromY,
    required this.toX, required this.toY,
    this.durationMs = 300,
  });
  final int fromX, fromY, toX, toY;
  final int durationMs;
}

/// Thrown by a backend for an expected device/transport failure. Tools catch
/// this and return ToolResult(ok:false, error:e.message) — they never rethrow.
class NativeException implements Exception {
  NativeException(this.message);
  final String message;
  @override
  String toString() => 'NativeException: $message';
}

/// The seam the watcher drives and the tools act through. AppiumBackend is the
/// first impl; FakeNativeBackend is the test impl. Per-platform behavior
/// (iOS ASWebAuthenticationSession consent, iOS Done vs Android back keyboard
/// dismiss, iOS-vs-Android readback attribute) lives INSIDE the impl, never in
/// the extension/tools.
///
/// Recognized [press] keys are platform-specific and documented on the impl,
/// NOT enforced by an allowlist on the tool (§3.1.1). iOS recognizes
/// `enter`/`return`/`done`/`consent_accept`; Android additively recognizes
/// `back`. An unrecognized key surfaces as a NativeException from the impl.
abstract class NativeBackend {
  /// Open the device session against an ALREADY-RUNNING Appium server and an
  /// ALREADY-BOOTED simulator (Appium /session with the proven caps). The
  /// backend does NOT spawn Appium or boot the sim (that lifecycle is m4).
  /// Idempotent.
  Future<void> connect();

  /// Out-of-band poll loop: emits a fresh NativeSnapshot each tick (reading
  /// /source for Appium, parsing the XCUITest XML — §5.3). This is the
  /// watcher's source — the snapshot IS the event payload (unlike tmux, which
  /// re-gathers per event).
  Stream<NativeSnapshot> watch();

  /// One-shot capture for seeding the cache in initialize() and for the
  /// post-action refresh tools call (the poll loop may not have ticked since
  /// the tap/text). Same payload shape as a watch() event.
  Future<NativeSnapshot> snapshot();

  /// Resolve a selector spec (a11y-id / label / xpath / rect args) against the
  /// device into a NativeTarget, walking the chain a11y-id -> label -> xpath ->
  /// rect-center (§5.4). Returns null when nothing resolves. `cached` is the
  /// current snapshot (for label-match and rect-center synthesis); pass it so
  /// resolution can fall back to a node rect without an extra round-trip.
  Future<NativeTarget?> resolve(NativeSelector selector, NativeSnapshot? cached);

  /// Tap a resolved target (element click, or a point tap for rect-center).
  Future<void> tap(NativeTarget target);

  /// Clear + type text into a resolved target, then dismiss the keyboard
  /// per-platform (iOS Done / Android back) INSIDE this method. Returns
  /// (readback, masked): `readback` is the GET .../attribute/value result;
  /// `masked` is derived from the ELEMENT TYPE (true iff the element is a
  /// SecureTextField), NOT from `readback != text` (§3.1.2).
  Future<({String readback, bool masked})> enterText(NativeTarget target, String text);

  /// A logical key press. iOS: 'enter'|'return'|'done'|'consent_accept' —
  /// 'consent_accept' issues POST /session/{id}/alert/accept (the iOS-only
  /// ASWebAuthenticationSession consent path). Android additive: 'back'.
  /// An unrecognized key throws NativeException.
  Future<void> press(String key);

  /// Swipe gesture (W3C actions / mobile: swipe).
  Future<void> swipe(NativeSwipe gesture);

  /// Tear down the device session (DELETE /session/{id}) and any HTTP client.
  /// Does NOT stop Appium or shut down the sim.
  Future<void> close();
}
```

#### 3.1.1 `press` key vocabulary — forward-to-backend, no tool allowlist

The `_PressTool` does NOT maintain a recognized-key allowlist. Keys are platform-specific and owned by the backend. The tool forwards any non-empty `key` string to `backend.press(key)` and catches `NativeException` into `ToolResult(ok:false, error: e.message)`. An unknown key surfaces as the **backend's** `NativeException` message (e.g. `unknown press key: foo`). There is no tool-level "unknown key" literal. Recognized keys (documented on the backend, §3.1): iOS `enter`/`return`/`done`/`consent_accept`; Android additively `back`. `consent_accept` is **iOS-only** → `POST /session/{id}/alert/accept`; Android's additive keys never include it, keeping the per-platform boundary crisp.

#### 3.1.2 `enterText` masked flag — element-type-derived, in the backend

`enterText` returns `(readback, masked)`. `masked` is `true` **iff the resolved element is a `XCUIElementTypeSecureTextField`** (the backend already knows the element type from the resolved node / the find), NOT `readback != text` — a `readback != typed` heuristic false-positives on OS-normalized non-secure input (trimmed whitespace, autocapitalization). The tool relays the backend's `masked` flag verbatim and never recomputes it. This is the FN3 mitigation: a secure field reads back masked bullets (non-empty, ≠ plaintext), and the `masked` signal is the element type, not the readback comparison.

### 3.2 `native_snapshot.dart` — the cached snapshot + node record

`NativeNode` carries the **canonical cross-host record schema** (§1.1) so an agent driving Flutter vs native sees a byte-identical record. **`rect` is a 4-int `[left, top, right, bottom]`** (NOT `{x,y,w,h}`, NOT doubles); optional fields are **omitted when empty** at serialization time, in the canonical key order `id, role, rect, label?, value?, state?, actions?, scroll?`.

```dart
@immutable
class NativeNode {
  const NativeNode({
    required this.id,         // dense per-session int (NOT the raw a11y-id)
    required this.role,       // 'button'|'textfield'|'link'|'text'|... (Flutter vocab)
    this.label,
    this.value,               // text-field contents / element value (see §5.3)
    required this.rect,       // [left, top, right, bottom] ints
    this.state = const <String>[],   // carried for schema parity; empty in m2 iOS
    this.actions = const <String>[],
    this.scroll,              // carried for schema parity; null in m2 iOS
    this.a11yId,              // raw OS accessibility identifier — selector tier 1
    this.xpath,               // node's synthesized/derived XPath — selector tier 3
  });
  final int id;
  final String role;
  final String? label;
  final String? value;
  final List<int> rect;
  final List<String> state;
  final List<String> actions;
  final Map<String, Object?>? scroll;
  final String? a11yId;
  final String? xpath;

  /// Emits the canonical cross-host record (§1.1), matching the updated
  /// Flutter _Rec.toJson key order EXACTLY: id/role/rect always present;
  /// label/value/state/actions/scroll OMITTED when null/empty. a11yId/xpath
  /// are NOT emitted to the wire (selector-internal); they live on the
  /// in-memory node only.
  Map<String, Object?> toRecord() {
    final m = <String, Object?>{'id': id, 'role': role, 'rect': rect};
    if (label != null && label!.isNotEmpty) m['label'] = label;
    if (value != null && value!.isNotEmpty) m['value'] = value;
    if (state.isNotEmpty) m['state'] = state;
    if (actions.isNotEmpty) m['actions'] = actions;
    if (scroll != null) m['scroll'] = scroll;
    return m;
  }
}

@immutable
class NativeSnapshot {
  const NativeSnapshot({required this.platform, required this.nodes});
  final String platform;            // 'ios' | 'android'
  final List<NativeNode> nodes;     // flattened a11y tree (document order)
}
```

### 3.3 Why `value` is first-class

The native a11y tree's first-class signal for a text field is its **current value** — what was typed — which is exactly what the selector/verification logic needs (the `enter_text` readback). The canonical schema (§1.1) makes `value` a peer of `label` on BOTH hosts: Flutter sources it from `SemanticsData.value`, native from the XCUITest `value` attribute. There is no divergence and no parked decision.

### 3.4 Bounded Flutter edit (the ONLY `leonard_flutter` change)

In `packages/leonard_flutter/lib/src/semantics/semantics_capture.dart`:

1. **Doc comment** (the schema line, currently `id, role, label?, state?, actions?, rect`): add `value?` so it reads `id, role, label?, value?, state?, actions?, rect` (canonical key order).
2. **`_Rec`**: add a `final String value;` field; thread it through the constructor (positional, after `label`, matching the existing positional style).
3. **`toJson`**: between the existing `if (label.isNotEmpty) m['label'] = label;` and `if (state.isNotEmpty) m['state'] = state;`, insert:
   ```dart
   if (value.isNotEmpty) m['value'] = value;
   ```
4. **`_walk`**: pass `d.value` (from `SemanticsData`) into the `_Rec(...)` construction (it sits alongside `d.label`).
5. **`semantics_capture_test.dart`** (pinned): add `'value'` to the schema allow-set (`btn.keys.toSet()` `isIn` set currently `{id, role, label, state, actions, rect, scroll}`), AND add a positive assertion: pump a `TextField`/`Slider` whose semantics carry a value and assert the emitted record has the expected `value` string.

Nothing else in `leonard_flutter` changes. `leonard_contract`, `leonard_host`, and the `ext.exploration.*` wire surface are untouched.

---

## 4. NativeExtension

`packages/leonard_native/lib/src/native_extension.dart`. A 1:1 clone of `TmuxExtension`'s structure.

### 4.1 Class + watcher (mirror `TmuxExtension`)

```dart
class NativeExtension extends LeonardExtension with PerceptionExtension {
  NativeExtension(this.backend);
  final NativeBackend backend;

  StreamSubscription<NativeSnapshot>? _sub;
  NativeSnapshot? _live;             // the CACHED snapshot
  bool _refreshing = false;          // retained for tmux parity (see AC11)
  bool _disposed = false;

  @override
  String get namespace => 'native';  // ^[a-z][a-z0-9_]*$ — registry validates

  @override
  List<LeonardTool> get tools => <LeonardTool>[
    _TapTool(this), _EnterTextTool(this), _PressTool(this), _SwipeTool(this),
  ];

  @override
  Future<void> initialize(ExtensionContext ctx) async {   // ONLY async-startup site
    await backend.connect();
    _sub = backend.watch().listen(
      (snap) { _live = snap; },                  // out-of-band, no re-gather
      onError: (Object _) { /* transient poll error: keep last-good _live */ },
      cancelOnError: false,                      // a poll error must not kill the host isolate
    );
    _live = await backend.snapshot();            // seed before first observation
  }

  @override
  void prepareForObservation() {}                  // no-op — watcher keeps _live current (ADR-0006)

  @override
  bool isPerceptionIdle() => _live == null;        // suppress fragment until first snapshot

  @override
  Seed buildPerception() => NativePerception(_live!);  // SYNCHRONOUS read of the cache

  @override
  Future<BusyState> busyState() async => BusyState.idle;

  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _sub?.cancel(); _sub = null;
    await backend.close();
  }

  /// Force-refresh the cache now (after a mutating tool), so the next
  /// observation reflects the tap/text without waiting for a poll tick.
  /// No-op after dispose; swallows transient failures to keep the last-good
  /// snapshot — exactly tmux's _refresh().
  Future<void> refreshNow() async {
    if (_disposed || _refreshing) return;
    _refreshing = true;
    try { _live = await backend.snapshot(); }
    on Object { /* keep last good */ }
    finally { _refreshing = false; }
  }
}
```

**`watch()` resilience (required).** The `backend.watch().listen` MUST set `onError` (keep the last-good `_live`) and `cancelOnError: false`. `AppiumBackend.watch()` is an HTTP poll loop; a transient `/source` poll error must surface on the stream as an error event and be swallowed here, NOT crash the host isolate. (tmux never propagated stream errors; an HTTP source can — this is the structural difference.) AC12 + a unit test pin this.

**Why `_live = snap` and not a re-gather** (the one real divergence from tmux): tmux's `PollObservationSource` emits opaque `TmuxEvent`s and the extension re-gathers via `gatherTmuxObservation` per tick. Here `backend.watch()` emits `Stream<NativeSnapshot>` directly, so the snapshot **is** the event payload — the listener just assigns `_live`. `backend.snapshot()`/`refreshNow()` still exist for the post-action immediate refresh, because the poll loop may not have ticked since the tap.

**ADR-0006 hard line:** `buildPerception()` returns `Seed`, no `Future`, no `await`. Any urge to query Appium at observe time is a design error — that work lives in `watch()`/`snapshot()`, started in `initialize()`.

### 4.2 `native_perception.dart` (mirror `TmuxPerception`)

Per the Flutter precedent (`core_perception.dart` carries the semantics record-list as a single `Field('semantics', List<Map>)` inside `Node('core', ...)`), the native fragment carries the per-node record list as **one `Field`**, NOT a Node-per-element subtree — so the wire shape is flat and the agent reads a list. **Decision: the field key is `elements`** (carrying the whole record list as one Field sidesteps sibling-name collisions — anonymous Auth0 fields can share empty a11y-ids).

```dart
class NativePerception extends StatelessPerception {
  const NativePerception(this.snapshot, {super.key});
  final NativeSnapshot snapshot;

  @override
  Seed build(PerceptionContext ctx) => Node('native', children: <Seed>[
    Field('platform', snapshot.platform),
    Field('node_count', snapshot.nodes.length),
    // Single Field carrying the record list, mirroring Flutter's
    // Field('semantics', List<Map>). Keyed 'elements' for native (decided).
    Field('elements', <Map<String, Object?>>[
      for (final n in snapshot.nodes) n.toRecord(),
    ]),
  ]);
}
```

This serializes (via the host's `serializePerceptionFragment`, verbatim assignment) to `value.extensions.native = {platform, node_count, elements: [ {id,role,rect,label?,value?,...}, ... ]}`. The harness reads native records from `extensions.native.elements` (the native fragment is **nested under `extensions.native`**, NOT promoted top-level the way the Flutter binding special-cases `core`).

> If a future change reverts to a Node-per-element tree, each Node name MUST be a unique key (use the dense `id`, not the raw a11y-id). For m2 it stays one `Field('elements', ...)`.

### 4.3 The four tools + selector chain

Each tool is a private nested `LeonardTool` holding a back-ref to the extension (tmux's `_SendKeysTool` shape). All four share one resolver. Tool `name` is a **bare token** (no `.`) — the registry prefixes `native.`. Bad/unresolvable input returns `ToolResult(ok:false, error:...)`; backend `NativeException`s are caught into `ok:false`; **never throw**.

Shared selector resolution (a helper on the extension, delegating to `backend.resolve`):

```dart
Future<NativeTarget?> _resolveTarget(Map<String, Object?> args) {
  final sel = NativeSelector(
    a11yId: args['id'] as String?,        // tier 1: a11y-id
    label:  args['label'] as String?,     // tier 2: label
    xpath:  args['xpath'] as String?,     // tier 3: XPath (load-bearing)
    rect:   (args['rect'] as List?)?.cast<int>(),  // tier 4: rect-center
  );
  return backend.resolve(sel, _live);     // backend walks the chain in order
}
```

The chain order is **a11y-id → label → XPath → rect-center**, evaluated inside `backend.resolve` (§5.4). The `via` field on the returned `NativeTarget` records which tier won (asserted in unit tests).

**`_TapTool`** (`name: 'tap'`):
```dart
JsonSchema get inputSchema => const JsonSchema({
  'type': 'object',
  'properties': {
    'id':    {'type': 'string', 'description': 'a11y identifier (tier 1)'},
    'label': {'type': 'string', 'description': 'visible label (tier 2)'},
    'xpath': {'type': 'string', 'description': "XPath, e.g. //XCUIElementTypeTextField[@name='Email address'] (tier 3)"},
    'rect':  {'type': 'array', 'items': {'type': 'integer'},
              'description': '[l,t,r,b]; taps the center (tier 4, last resort)'},
  },
  'additionalProperties': false,
});
Future<ToolResult> call(Map<String,Object?> args) async {
  final t = await _ext._resolveTarget(args);
  if (t == null) return const ToolResult(ok:false, error:'no element matched selector');
  try { await _ext.backend.tap(t); }
  on NativeException catch (e) { return ToolResult(ok:false, error:e.message); }
  await _ext.refreshNow();                          // refresh-after-act
  return ToolResult(ok:true, value: {'via': t.via});
}
```

**`_EnterTextTool`** (`name: 'enter_text'`): same selector props **plus** `text` (required string). Resolves the target, calls `backend.enterText(target, text)` (which clears, types, and dismisses the keyboard per-platform inside the backend), then `refreshNow()`. Returns `ToolResult(ok:true, value:{'via':..., 'readback': r.readback, 'masked': r.masked})` where `(readback, masked)` is the backend's return (§3.1.2 — `masked` is element-type-derived). **Secure-field caveat (spike FN3):** a password field reads back masked bullets — non-empty, ≠ plaintext; the tool reports the readback + `masked` and does NOT assert plaintext equality. Missing `text` → `ToolResult(ok:false, error:'text is required')`.

**`_PressTool`** (`name: 'press'`): one required prop `key` (string). Forwards any non-empty key to `backend.press(key)` (no tool allowlist — §3.1.1); catches `NativeException` into `ToolResult(ok:false, error: e.message)`. Empty/missing `key` → `ToolResult(ok:false, error:'key is required')`. `refreshNow()` after a successful press.

**`_SwipeTool`** (`name: 'swipe'`): props `from` (`[x,y]` int array, required), `to` (`[x,y]` int array, required), `duration_ms` (int, optional, default 300). Validates both arrays are 2-int; builds `NativeSwipe`; calls `backend.swipe(...)`; `refreshNow()` after. Bad/short arrays → `ToolResult(ok:false, ...)`.

**Consent + keyboard dismiss are backend concerns, not contract concerns.** Consent is reached via `native.press {key:'consent_accept'}` (→ `POST /alert/accept`, iOS-only). Keyboard dismiss happens **inside** `backend.enterText` (iOS "Done" tap when present / no-op on iOS 26 / Android back) so the extension/tools stay platform-agnostic and Android stays additive.

### 4.4 Host entrypoint (`bin/leonard_native_host.dart`)

A clone of `example/tmux_vm_host.dart`, placed in `bin/`. It parses args, builds `AppiumBackend`, wraps it in `NativeExtension`, installs it on `ExplorationHost`, prints the ready marker, and waits for a signal. It does NOT boot Appium or the simulator.

Arg surface (the launcher in m4 will pass these; m2 just parses them):
- `--server <url>` (default `http://127.0.0.1:4723`)
- `--udid <booted-sim-udid>` (required)
- `--app <Runner.app path>` (required)
- `--platform ios` (default `ios`)

Shape (mirroring the tmux host):
```dart
Future<void> main(List<String> args) async {
  final o = _parseArgs(args);   // --server/--udid/--app/--platform
  final backend = AppiumBackend(
    server: Uri.parse(o['server'] ?? 'http://127.0.0.1:4723'),
    platform: o['platform'] ?? 'ios',
    udid: o['udid']!, app: o['app']!,
  );
  final ext = NativeExtension(backend);
  final host = ExplorationHost(extensions: <LeonardExtension>[ext]);
  await host.install();
  stdout.writeln('LEONARD_HOST_READY');
  final done = Completer<void>();
  for (final sig in <ProcessSignal>[ProcessSignal.sigterm, ProcessSignal.sigint]) {
    sig.watch().listen((_) async {
      await ext.dispose();          // cancels watcher + backend.close()
      if (!done.isCompleted) done.complete();
    });
  }
  await done.future;
  exit(0);
}
```

---

## 5. AppiumBackend

`packages/leonard_native/lib/src/appium_backend.dart` — a hardened production lift of `docs/design/leonard-native-appium/backend_skeleton.dart`, implementing `NativeBackend` over W3C WebDriver HTTP against a **local Appium server** (default `http://127.0.0.1:4723`). It reproduces the **proven spike recipe** (`~/lenny-spike/RESULTS.md`, GREEN 2026-06-20: Appium 3.5.2 + xcuitest 11.12.2, Xcode 26.5, iOS 26 sim).

### 5.1 Construction & caps

```dart
AppiumBackend({
  Uri? server,                          // default http://127.0.0.1:4723
  required String platform,             // 'ios' (m2); 'android' deferred
  required String udid,                 // booted simulator udid (B8: required, no default)
  required String app,                  // path to Runner.app (B8: required, no default)
  String osVersion = '26',
  Duration pollInterval = const Duration(seconds: 1),
});
```

`connect()` POSTs `/session` with `{capabilities:{alwaysMatch:<caps>, firstMatch:[{}]}}`, reproducing the GREEN caps exactly:

```
platformName: 'iOS'
appium:automationName: 'XCUITest'
appium:udid: <udid>                                  // the booted sim
appium:app: <Runner.app path>
appium:forceSimulatorSoftwareKeyboardPresence: true
appium:noReset: true
```

> There is NO `bundleId` and NO `deviceName` cap (skeleton hardening B8 + the fit-critic note): the proven recipe targets by `udid` + `app`, not bundleId/deviceName. Delete those from the skeleton lift.

Stash the returned `sessionId` (`value.sessionId ?? top.sessionId`). The W3C element key is `"element-6066-11e4-a52e-4f735466cecf"` — `find`/`resolve` return `value.values.first` as the element handle.

### 5.2 Endpoints (W3C, from the proven recipe)

| Operation | HTTP | Notes |
|---|---|---|
| Open session | `POST /session` | caps above; capture `sessionId`. |
| Set context | `POST /session/{id}/context {name:'NATIVE_APP'}` | XCUITest NATIVE_APP context sees the ASWebAuthenticationSession web inputs (spike B1 retired). |
| Find by strategy | `POST /session/{id}/element {using:<strategy>, value:<v>}` | the resolution primitive; retry-with-timeout guard (§5.4). |
| Tap element | `POST /session/{id}/element/{eid}/click` | element tier. |
| Tap point (rect-center) | `POST /session/{id}/actions` (W3C pointer) | last-resort tap at `((l+r)/2,(t+b)/2)`. |
| Clear + type | `POST /element/{eid}/clear` then `POST /element/{eid}/value {text:<t>}` | type via `/value`. |
| Read back value | `GET /session/{id}/element/{eid}/attribute/value` | iOS `value`; Android `attribute/text` (branch on platform — FN4). |
| **Accept consent** | `POST /session/{id}/alert/accept` | **KEY finding**: the ASWebAuthenticationSession consent ("… Wants to Use … to Sign In") is a SEPARATE SpringBoard process, NOT in `/source` — an XPath find for "Continue" MISSES it. Accept it via the W3C alert endpoint. This is `press('consent_accept')`. |
| Poll a11y tree | `GET /session/{id}/source` | the XCUITest XML a11y tree — the perception source, parsed into `List<NativeNode>` (§5.3). |
| Keyboard dismiss | iOS: tap "Done" if present (no-op on iOS 26); Android: back via the UIA2-supported route | inside `enterText`; per-platform; non-fatal (B6). |
| Quit | `DELETE /session/{id}` | `close()`; best-effort, releases the WDA session so it doesn't strand. |

Transport (`_post`/`_get`/`_unwrap`) is lifted from the skeleton WITH the **B5** hardening: `_unwrap` checks `statusCode` first; on non-2xx OR a `value.error` envelope it throws `NativeException` (including status + raw body); `jsonDecode` is wrapped so a non-JSON/HTML/empty body throws `NativeException('non-JSON response: …')`, never a bare `FormatException`. This keeps `find`'s retry guard load-bearing.

### 5.3 `watch()` / `snapshot()` — the a11y poll + XCUITest-XML parser

`watch()` returns a `Stream<NativeSnapshot>` driven by a periodic timer (`pollInterval`): each tick `GET /source`, **parse the XCUITest XML into `List<NativeNode>`**, emit `NativeSnapshot(platform:'ios', nodes:...)`. A transient poll error is emitted as a stream error (the extension swallows it — §4.1). `snapshot()` does one such pass on demand (seeding + `refreshNow`).

**The parser (`_parseSource(String xml) → List<NativeNode>`)** uses `package:xml`:

1. **Parse**: `XmlDocument.parse(xml)`. The root is `<AppiumAUT>`; descend into its `XmlElement` children.
2. **Recursive descent, document order**: walk every descendant `XmlElement` depth-first. Each element is one candidate node. Maintain an output `List<NativeNode>` appended in document order (the flatten order). Maintain a `Map<XmlElement,int>` so the dense id is stable per element ref within the parse.
3. **Attribute map** read per element (missing → null/empty): `type` (e.g. `XCUIElementTypeTextField`), `name`, `label`, `value`, `x`, `y`, `width`, `height`, `enabled`, `visible`.
4. **Filter**: skip pure structural containers that carry no useful signal — drop an element when it has NO `name` AND NO `label` AND NO `value` AND its `type` maps to the default `text` role (i.e. anonymous `XCUIElementTypeOther`/`Window`/`Application` scaffolding). Keep every element that has a name/label/value OR a non-`text` role. (This collapses the deep `XCUIElementTypeOther` nesting in the fixture to the handful of real controls.)
5. **`role`** — map `XCUIElementType*` → Flutter vocab:
   `Button`→`button`; `TextField`→`textfield`; `SecureTextField`→`textfield`; `Link`→`link`; `StaticText`→`text`; `Image`→`image`; `Switch`→`switch`; default→`text`.
6. **`label`**: the `label` attribute (fall back to `name` when `label` is empty).
7. **`value`**: the `value` attribute (text contents; masked bullets for a `SecureTextField`). Omitted when empty.
8. **`rect`**: convert `{x,y,width,height}` → `[x, y, x+width, y+height]` as **rounded ints**, matching Flutter's `[l,t,r,b]`.
9. **`actions`**: best-effort from `traits`/`enabled` (may be empty in m2). `state`/`scroll`: left empty/null in m2 (schema parity only).
10. **`id`** — dense per-session int: a stable counter keyed by the element ref (`Map<XmlElement,int>` → `1`-based), mirroring `_stableIdFor`. NOT the raw a11y string.
11. **`a11yId`**: the `name` attribute (selector tier 1) when present.
12. **`xpath`** — DETERMINISTIC synthesis for EVERY kept node, computed in document order:
    - If the node has a unique `name`, prefer `//XCUIElementType<T>[@name='<name>']` when that name is unique among kept nodes of type `<T>`.
    - Otherwise synthesize a **positional** xpath: `(//XCUIElementType<T>)[n]` where `n` is the 1-based document-order index of this node among ALL nodes of type `<T>` in the parse (anonymous nodes included). This is the load-bearing rule for anonymous + positional Auth0 fields.

**Worked example** — three real nodes from `~/lenny-spike/spike_source.xml` (checked in as `test/fixtures/auth0_source.xml`):

- `<XCUIElementTypeButton name="Log in" label="Log in" x="156" y="450" width="90" height="48" .../>`
  → `NativeNode(id:1, role:'button', label:'Log in', rect:[156,450,246,498], a11yId:'Log in', xpath:"//XCUIElementTypeButton[@name='Log in']")`.
- `<XCUIElementTypeTextField name="Email address" label="Email address" x="40" y="376" width="322" height="52" placeholderValue="" .../>`
  → `NativeNode(id:N, role:'textfield', label:'Email address', rect:[40,376,362,428], a11yId:'Email address', xpath:"//XCUIElementTypeTextField[@name='Email address']")` — `value` omitted (empty before typing).
- `<XCUIElementTypeSecureTextField name="Password" label="Password" x="41" y="441" width="276" height="52" placeholderValue="" .../>`
  → `NativeNode(id:M, role:'textfield', label:'Password', rect:[41,441,317,493], a11yId:'Password', xpath:"//XCUIElementTypeSecureTextField[@name='Password']")` — `value` omitted before typing; after `enter_text` it reads back masked bullets so `value` is present and `masked:true`.

`toRecord()` for the Log in button emits exactly `{id:1, role:'button', rect:[156,450,246,498], label:'Log in'}` (no `value`/`state`/`actions`/`scroll` — omitted).

### 5.4 `resolve()` — the selector chain inside the backend

`resolve(selector, cached)` walks **a11y-id → label → XPath → rect-center**, returning the first tier that resolves (else `null`):

1. **a11y-id** (`selector.a11yId != null`): `find` via the accessibility-id strategy — `POST /session/{id}/element {using:'accessibility id', value:<a11yId>}`. On hit → `NativeTarget(elementId, via:'a11y-id')`.
2. **label** (`selector.label != null`): match the cached node whose `label == selector.label`, then resolve THAT node deterministically (in order):
   - its `a11yId` if present → `find {using:'accessibility id', value:<a11yId>}`;
   - else its `xpath` if present → `find {using:'xpath', value:<xpath>}`;
   - else a **synthesized positional xpath** from the node's document-order index (§5.3 step 12) → `find {using:'xpath', value:<synthesized>}`;
   - if no cached node matches the label → fall through to tier 3/4.
   On hit → `NativeTarget(elementId, via:'label')`.
3. **XPath** (`selector.xpath != null`, load-bearing): `find {using:'xpath', value:<selector.xpath>}` (e.g. `//XCUIElementTypeTextField[@name='Email address']`). On hit → `NativeTarget(elementId, via:'xpath')`. This is what resolves anonymous + positional Auth0 fields.
4. **rect-center** (`selector.rect != null`, OR a cached node rect is available): return `NativeTarget(point:(((l+r)/2).round(), ((t+b)/2).round()), via:'rect-center')` — `tap` issues a W3C pointer action at that point.

There is no "find its XPath / accessibility id" hand-wave: tier 2 is fully determined by the cached node's `a11yId`/`xpath`/synthesized-positional-xpath, in that order.

### 5.5 Hardening (apply the skeleton's documented mutations)

From `backend_skeleton.dart`'s header + `spec.md`:
- **B5**: `_unwrap` honors HTTP status + non-JSON bodies (throw `NativeException`, not `FormatException`) so the find retry guard holds.
- **FN4**: `readValue` branches iOS `attribute/value` vs Android `attribute/text`.
- **FN3**: `enterText` returns `(readback, masked)` where `masked` is derived from the resolved ELEMENT TYPE (SecureTextField), NOT `readback != typed` (§3.1.2); assert non-empty + masked, never equality/length.
- **FP1/FP2**: optional right-page `/source` guard (assert the tenant host, e.g. `dev-y1gwg3ay5b5rl17n.us.auth0.com`, present) before driving the login form — a confidence gate, not a hard requirement for the tool surface.
- **B6**: Android back / keyboard-dismiss route uses the UIA2-supported path and is wrapped non-fatal (may 404 on UIA2) — structural only in m2.
- **B8**: `udid`/`app` are REQUIRED constructor args (no hardcoded bundle/device defaults).
- **Skeleton-lift deletions (fit-critic):** DELETE the skeleton's xpath-based consent block (`iosConsentTitle`/`iosContinue` find-and-tap, skeleton L116-118,L173-178) — consent is `POST /session/{id}/alert/accept` (`press('consent_accept')`), because RESULTS.md proves the SpringBoard consent is NOT in `/source` and an xpath "Continue" find misses it. DELETE the `bundleId`/`deviceName` caps; use `udid`/`app`/`forceSimulatorSoftwareKeyboardPresence` (§5.1).

---

## 6. Acceptance criteria

Each is independently verifiable; the check method is named.

1. **Package builds & analyzes clean.** `melos run analyze` and `melos run format` pass with `leonard_native` present (and the bounded `leonard_flutter` edit applied). *Check:* CI / `melos run analyze` + `melos run format`.
2. **Namespace + tool manifest.** `NativeExtension(fake).namespace == 'native'`; `tools` are exactly `tap, enter_text, press, swipe` as **bare** tokens (no `.`). *Check:* `native_extension_test.dart` asserts `ext.tools.map((t)=>t.name)`; `native_host_test.dart` asserts `ExplorationHost.handshakeJson()` lists `native.tap/native.enter_text/native.press/native.swipe`.
3. **Idle-before / stateful-after.** `isPerceptionIdle()` is `true` before `initialize()` and `false` after (snapshot seeded). *Check:* unit test asserts the flip across `initialize()` with `FakeNativeBackend`, `addTearDown(ext.dispose)`.
4. **`buildPerception()` return type is `Seed`, not `Future<Seed>` — analyzer-enforced.** *Check:* compiles; the synchronous signature makes an `await`-in-body impossible by construction.
5. **`initialize()` is the only async-startup site.** The watcher feeds `_live` out-of-band; no observe-time I/O (ADR-0006). *Check:* code review of `native_extension.dart`; reinforced by AC3 (the idle→stateful flip happens without awaiting at observe time).
6. **Fragment record shape matches the canonical cross-host schema.** The native fragment serializes to `extensions.native = {platform, node_count, elements: [...]}` where each element is `{id:int, role:String, rect:[l,t,r,b] ints, label?, value?, state?, actions?, scroll?}` with optional fields **omitted when empty**, in canonical key order. *Check:* unit test mounts `ext.buildPerception()` via `PerceptionOwner` → `serializePerceptionFragment` and asserts the keys/shape — including omission of empty fields and presence of `value` on a node that has one. This is the SAME schema the updated `_Rec.toJson` emits (§1.1).
7. **Bounded Flutter `value` addition + test update.** `_Rec` carries a `value` field sourced from `SemanticsData.value`; `toJson` emits `value` (between `label` and `state`) when non-empty; the doc comment lists `value?`; `semantics_capture_test.dart` admits `value` in its schema allow-set AND positively asserts `value` on a value-bearing node (TextField/Slider). `leonard_contract`/`leonard_host`/wire surface unchanged. *Check:* the updated `semantics_capture_test.dart` passes under `melos run test`; diff review confirms the edit is confined to `semantics_capture.dart` + its test.
8. **`native.tap` reaches the backend with the correctly resolved selector.** A tap with `{id:...}` resolves `via:'a11y-id'`; with only `{xpath:...}` resolves `via:'xpath'`; with only `{rect:[...]}` resolves `via:'rect-center'`; a `{label:...}` against an anonymous cached node (no a11yId) resolves `via:'label'` through a synthesized positional xpath. *Check:* unit test inspects `FakeNativeBackend.calls` and the `via` on the recorded `NativeTarget` for each tier — including the load-bearing XPath and the anonymous-label→positional-xpath case.
9. **`native.enter_text` types + reports element-type-derived masked readback.** For a normal field, `ok:true` with `readback == typed, masked:false`; for a secure field, `ok:true` with `masked:true` and `readback` non-empty ≠ typed. `masked` comes from the backend's element-type signal, NOT a `readback != typed` heuristic. *Check:* unit test with `FakeNativeBackend` scripted to return `(readback, masked)` per field type; asserts the tool relays `masked` verbatim.
10. **Keyboard dismiss is per-platform and inside `AppiumBackend.enterText`.** The dismiss branch (iOS Done / iOS-26 no-op / Android back) lives INSIDE `AppiumBackend.enterText`, not in the extension/tool, and is not interceptable through the seam. *Check:* code review confirms the branch lives in `AppiumBackend.enterText`; live e2e (AC14) exercises it on iOS. (No fake-recorded dismiss assertion — the seam has no dismiss method.)
11. **Consent path issues the W3C alert/accept.** `native.press {key:'consent_accept'}` causes the backend to invoke its accept path. *Check:* unit test asserts `FakeNativeBackend.calls` records a `consent_accept` press; in `AppiumBackend`, code review + live e2e confirm it maps to `POST /session/{id}/alert/accept`.
12. **`watch()` resilience.** A transient error pushed onto `backend.watch()`'s stream does NOT crash the host isolate and does NOT clear the last-good snapshot. *Check:* unit test where `FakeNativeBackend` pushes an error event onto the `watch()` stream after a good snapshot; asserts the extension survives (`isPerceptionIdle()` stays false, `buildPerception()` still returns the last good fragment).
13. **Structured errors, never throws.** Missing required args (`enter_text` without `text`, `press` without `key`, `swipe` with a malformed array) and an unresolvable selector return `ToolResult(ok:false, error:...)`; a backend `NativeException` (incl. an unknown `press` key) is caught into `ok:false`. *Check:* unit tests assert `res.ok == false && res.error != null` (mirroring tmux's missing-args test).
14. **Refresh-after-act; `refreshNow()` is a no-op after dispose.** Every mutating tool calls `refreshNow()` after a successful backend verb, so the next observation reflects the change without waiting for a poll tick; calling `refreshNow()` after `dispose()` leaves `_live` unchanged and makes no `backend.snapshot()` call. *Check:* unit test scripts the fake to change its `snapshot()` payload after a `tap`, asserts the post-tap `buildPerception()` reflects it; then disposes, calls `refreshNow()`, and asserts `_live` unchanged / no extra `snapshot` call recorded. (`_refreshing` is retained for tmux parity only and is NOT separately asserted.)
15. **Host wire shape round-trips.** `ExplorationHost(extensions:[NativeExtension(fake)])` → `handshakeJson` lists the four tools + `bindingType:'LeonardHost'` + `capabilities:[]`; `observationJson` round-trips through `Observation.fromJson` with `extensions.native` present; `invokeToolJson('native.tap', {...stringified args...})` returns `{ok:true,...}`. *Check:* `native_host_test.dart` (modeled on `exploration_host_test.dart`), remembering args cross the wire JSON-encoded as strings.
16. **XCUITest-XML parser + xpath synthesis.** `_parseSource` over the checked-in `test/fixtures/auth0_source.xml` yields `NativeNode`s for the Log in button, the Email TextField, and the Password SecureTextField with the rects, roles, labels, a11yIds, and xpaths in §5.3's worked example; anonymous nodes get a deterministic positional `(//XCUIElementType<T>)[n]` xpath. *Check:* `appium_xml_parser_test.dart` asserts the parsed list against the §5.3 worked example (rect conversion, role vocab, dense ids in document order, named-vs-positional xpath synthesis).
17. **Standalone host boots & is driveable (live).** `dart run --enable-vm-service=0 --disable-service-auth-codes bin/leonard_native_host.dart --udid <sim> --app <Runner.app>` against a booted iOS sim + running Appium prints `LEONARD_HOST_READY`, the VM prints its URI, and a `LeonardSession` can handshake, observe the `native` fragment, and drive the Auth0 login to a masked-password readback. *Check:* `native_host_e2e_test.dart` (self-skips when Appium/sim absent) — the live dogfood tier. Driver API: `LeonardSession.connect(wsUri)` → `start(goal, const LeonardConfig())` → `act({'name':'native.tap', 'args':{...}})` and `observe()` reading `obs.extensions['native']`, matching `host_e2e_test.dart`'s proven pattern.
18. **Reproduces the GREEN spike.** Live e2e: tap "Log in" → accept consent via `press('consent_accept')` (alert/accept) → type nonce email (readback == typed) → type password (readback masked, non-empty, ≠ plaintext) → stop before SIGN IN. *Check:* the e2e asserts `emailOk && passwordMasked` exactly as `o1_drive.py` did.
19. **No contract/host/wire changes.** `git diff feat/leonard-native..HEAD` touches only `packages/leonard_native/**`, the root workspace registration, AND the bounded edit to `packages/leonard_flutter/lib/src/semantics/semantics_capture.dart` (+ its test) — `leonard_contract`, `leonard_host`, and the `ext.exploration.*` wire surface are byte-unchanged. *Check:* diff review.

---

## 7. Implementation plan (ordered, file-by-file)

All on `feat/leonard-native`. Branch a working branch off it if desired, but base/PR target is `feat/leonard-native`, not `main`.

1. **Scaffold the package.** `packages/leonard_native/pubspec.yaml` (§2.1, incl. `xml: ^6.5.0`), `analysis_options.yaml` (copy tmux), `CHANGELOG.md`, `README.md`. Register in the root workspace + Melos globs. Run `dart pub get` / `melos bootstrap`.
2. **Bounded Flutter edit (§3.4).** Add `value` to `_Rec` + `toJson` + the doc comment in `semantics_capture.dart`, thread `d.value` through `_walk`, and update `semantics_capture_test.dart` (schema allow-set + positive value assertion). Run `melos run test` for `leonard_flutter` to confirm green. (AC7.)
3. **`lib/src/native_snapshot.dart`** — `NativeNode` (+ `toRecord()` emitting the canonical schema, §3.2) and `NativeSnapshot`. Pure value types, no deps beyond `meta`.
4. **`lib/src/native_backend.dart`** — `NativeBackend` abstract seam, `NativeSelector`, `NativeTarget`, `NativeSwipe`, `NativeException`. No impl. (Note the `enterText` `(readback, masked)` return and the press-key doc.)
5. **`lib/src/native_perception.dart`** — `NativePerception extends StatelessPerception` projecting one `Field('elements', List<Map>)` (§4.2).
6. **`lib/src/native_extension.dart`** — `NativeExtension` (watcher triad with resilient `watch().listen`: §4.1) + the four private tool classes + `_resolveTarget` selector helper (§4.3). Mirror `tmux_extension.dart`, swapping the seam.
7. **`lib/src/fake_native_backend.dart`** — `FakeNativeBackend implements NativeBackend`: a `calls` list (records `tap`/`enterText`/`press`/`swipe`/`resolve` with the resolved `NativeTarget`/`via`), a `StreamController<NativeSnapshot>` the test pushes into (incl. error events) for `watch()`, a settable `snapshot()` payload, and a scriptable `resolve()` (canned `NativeTarget` per tier incl. anonymous-label→positional-xpath; a secure-field `enterText` returning `(masked, true)`). Ship in `lib/`, like `FakeTmuxExecutor`.
8. **`lib/leonard_native.dart`** — the barrel (§2.2).
9. **`test/native_extension_test.dart`** — UNIT, modeled on `tmux_extension_test.dart`: manifest, idle→stateful, fragment shape via mount/serialize, per-tier selector resolution, masked readback, refresh-after-act + post-dispose no-op, watch resilience, structured errors. (AC 2,3,4,6,8,9,12,13,14.)
10. **`test/native_host_test.dart`** — UNIT, modeled on `exploration_host_test.dart`: handshake/observation/invoke over `ExplorationHost(extensions:[NativeExtension(fake)])` + a `consent_accept` press recorded on the fake. (AC15; supports 2,11.)
11. **`lib/src/appium_backend.dart`** — `AppiumBackend implements NativeBackend`: lift `backend_skeleton.dart`, apply ALL hardening (B5/FN3/FN4/FP1/FP2/B6/B8 + the skeleton-lift deletions in §5.5), implement `watch`/`snapshot` (source poll + `_parseSource` XML→`NativeNode` parser + rect conversion + dense-id map + xpath synthesis, §5.3), `resolve` (the 4-tier chain, §5.4), `tap`/`enterText`(element-type masked)/`press`(incl. `consent_accept`→alert/accept)/`swipe`/`close`. (AC 9,10,11,18 live behavior; AC16 parser.)
12. **`test/fixtures/auth0_source.xml`** — a checked-in fixture derived from `~/lenny-spike/spike_source.xml` (the Auth0 login subtree: the WebView form with Email/Password/Continue + the host Log in button).
13. **`test/appium_xml_parser_test.dart`** — UNIT: `_parseSource(fixture)` vs the §5.3 worked example (rects, roles, labels, a11yIds, dense ids, named + positional xpath). (AC16.) Expose `_parseSource` via a `@visibleForTesting` top-level/static if needed.
14. **`bin/leonard_native_host.dart`** — clone `tmux_vm_host.dart` into `bin/` (§4.4): parse `--server/--udid/--app/--platform`, build `AppiumBackend`, `NativeExtension`, `ExplorationHost`, `await host.install()`, print `LEONARD_HOST_READY`, `Completer` + SIGTERM/SIGINT → `ext.dispose()`, `exit(0)`. (AC17 boot.)
15. **`test/native_host_e2e_test.dart`** — LIVE e2e, modeled on `host_e2e_test.dart`: `@Timeout(Duration(seconds: 240))`, an Appium+sim presence gate that self-skips, `_hostScript()` resolver (`bin/` + `packages/leonard_native/bin/`), spawn host with `--enable-vm-service=0 --disable-service-auth-codes`, scrape URI + `LEONARD_HOST_READY`, derive ws URI, `LeonardSession.connect/start/act/observe`, drive the Auth0 flow, assert email-exact + password-masked. (AC17,18.)
16. **`melos run analyze` + `melos run format` + `melos run test`** all green (e2e + Flutter value test included; live e2e self-skips without hardware). Commit on `feat/leonard-native`. Push only when the user asks (factory lands `feat/leonard-native` itself later; m2 stacks onto it).

---

## 8. Validation plan

**Test taxonomy (house rule — hard constraint):** a test against `FakeNativeBackend` is a **UNIT test**, not e2e, even when it spans extension + host + contract. Reserve "e2e" strictly for the test that talks to a **real Appium server driving a real iOS simulator**, and that test MUST self-skip when Appium/the sim is absent. There is no root `dart_test.yaml` and the Melos `test` scripts use no `--exclude-tags`; live tests are kept out of the default run **by self-skip only** (mirror `host_e2e_test.dart`'s `_tmuxPresent()` gate). Do NOT introduce a new tag — `perf` is the only sanctioned tag in this repo and is unrelated.

### Unit tier (runs under default `melos run test`, no hardware) — `FakeNativeBackend`

The bulk of validation. `FakeNativeBackend` is the **only** substitution; `NativeExtension`, `NativePerception`, the contract dispatch, and `ExplorationHost` are all real production classes. `AppiumBackend._parseSource` is unit-tested against a checked-in XML fixture (no device).

- **`native_extension_test.dart`** — the watcher arc (idle→initialize→stateful→dispose, `addTearDown(ext.dispose)`); `buildPerception()` fragment shape via `PerceptionOwner().mountRoot(...)` → `serializePerceptionFragment` → assert-on-map (canonical record keys incl. `value`, omit-empty); per-tier selector resolution by inspecting `calls`/`via` (a11y-id, label incl. anonymous→positional-xpath, **XPath**, rect-center); `enter_text` element-type masked readback; refresh-after-act + post-dispose no-op; **watch resilience** (push an error onto the `watch()` stream, assert the host survives + keeps the last snapshot); structured errors (missing `text`/`key`, malformed `swipe`, unresolvable selector, unknown press key) → `ok:false`. **Covers AC 2, 3, 4, 6, 8, 9, 12, 13, 14.**
- **`native_host_test.dart`** — `ExplorationHost(extensions:[NativeExtension(fake)])`: handshake lists `native.{tap,enter_text,press,swipe}` + `bindingType:'LeonardHost'` + `capabilities:[]`; observation round-trips through `Observation.fromJson` with `extensions.native` present; `invokeToolJson('native.tap', {...})` with **stringified** arg values returns `{ok:true}`; a `press {key:'consent_accept'}` records the consent call on the fake. **Covers AC 11(fake-level), 15.**
- **`appium_xml_parser_test.dart`** — `_parseSource(test/fixtures/auth0_source.xml)` vs the §5.3 worked example: Log in button / Email TextField / Password SecureTextField with the right rects (`{x,y,w,h}`→`[l,t,r,b]`), role vocab, labels, a11yIds, dense document-order ids, and named-vs-synthesized-positional xpath. **Covers AC 16.**

### Live dogfood tier (excluded from default run by self-skip) — real Appium + iOS sim

- **`native_host_e2e_test.dart`** — `@Timeout(Duration(seconds: 240))`; gate: Appium reachable + a booted iOS sim (operator-provisioned — the host does NOT boot them); emit a single skipped test when absent, exactly like the tmux/dogfood precedents. Spawns `bin/leonard_native_host.dart` under `--enable-vm-service=0 --disable-service-auth-codes`, scrapes URI + `LEONARD_HOST_READY`, derives ws, `LeonardSession.connect → start → act → observe`, drives: tap "Log in" → `press('consent_accept')` → `enter_text` email (assert `obs.extensions['native']` + readback == nonce) → `enter_text` password (assert masked, non-empty, ≠ plaintext), **stop before SIGN IN** (m5 owns sign-in/callback/resume). **Covers AC 17, 18.** Android is NOT exercised here (deferred). This is the ONLY tier that proves `AppiumBackend`'s real W3C wiring (AC 11, 18 at the HTTP level, and 10 — iOS dismiss).

### Criterion → coverage map

| AC | Tier |
|---|---|
| 1 analyze/format clean | CI (`melos run analyze`/`format`) |
| 2 namespace+manifest | unit (ext + host) |
| 3 idle→stateful | unit |
| 4 sync buildPerception (analyzer) | compile |
| 5 only-async-startup-site | code review (reinforced by unit AC3) |
| 6 canonical fragment shape | unit |
| 7 bounded Flutter value edit | unit (`semantics_capture_test`) + diff review |
| 8 selector chain (incl. XPath + anon-label) | unit |
| 9 enter_text element-type masked readback | unit |
| 10 keyboard dismiss in AppiumBackend.enterText | code review + **live** (iOS) |
| 11 consent alert/accept | unit (fake records it) + **live** (real `POST /alert/accept`) |
| 12 watch() resilience | unit |
| 13 structured errors | unit |
| 14 refresh-after-act + post-dispose no-op | unit |
| 15 host wire round-trip | unit |
| 16 XCUITest-XML parser + xpath synthesis | unit (fixture) |
| 17 standalone host boots & driveable | **live** dogfood |
| 18 reproduces GREEN spike | **live** dogfood |
| 19 no contract/host/wire changes | diff review |

**Deferred to live (cannot be unit-covered):** real W3C endpoint behavior (alert/accept reaching SpringBoard, masked secure-field readback from a real field), iOS keyboard dismiss inside `enterText`, and the full Auth0 drive — AC 17 & 18, plus the HTTP-level halves of 10 & 11. The XML parser fidelity IS unit-covered (AC16) against the real `/source` fixture, so it is not deferred.
