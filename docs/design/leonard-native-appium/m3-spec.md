# lenny-qxx.3 — leonard_native m3: Multi-Host Attach (Build Spec)

**Base branch:** `feat/leonard-native` (the epic and m2/m4 stack here — do NOT land m3 to `main`). m3 builds on top of m4, which is already landed on this branch.
**Package under change:** `packages/leonard_agent` (the harness — adds the N-host attach/merge/route surface) + `packages/leonard_cli` (`leonard_drive` consumes m4's `DualLaunchHandle` to drive a dual-host session). `leonard_agent` stays Flutter- and `dart:io`-free; all process/launch I/O stays in `leonard_cli`.
**Status of dependencies (both LANDED on `feat/leonard-native`):**
- **m2** (`lenny-qxx.2`) — the pure-Dart native host: `ExplorationHost` + `NativeExtension` (namespace `native`, tools `tap`/`enter_text`/`press`/`swipe`) + `AppiumBackend`. Serves the SAME `ext.exploration.*` surface (handshake + `get_stable_observation` + per-tool dispatch) as the Flutter binding. (Verified: `packages/leonard_native/lib/src/native_extension.dart:36` — `String get namespace => 'native';`.)
- **m4** (`lenny-qxx.4`) — the launch lifecycle: `leonard_drive up` (native dual path, `_upDual`) boots a Flutter target + the native host against ONE shared device and produces a **`DualLaunchHandle`** (`packages/leonard_cli/lib/src/launcher.dart:328`) exposing two `ws://…/ws` endpoints — `flutterWsUri` (`= flutter.wsUri`) and `nativeEndpoint` (`= native.wsUri`) — plus `deviceId`. m3 is the **agent-loop CONSUMER** that attaches a session to **both** endpoints.

---

## 1. Goal & Scope

Today the harness attaches to exactly **one** VM-service endpoint. `LeonardSession` (`packages/leonard_agent/lib/src/session.dart`) wraps **one** `VmServiceClient` (one ws URI, one pinned isolate), one `ObservationPuller`, one `_handshake`, one `_prevObservation` diff baseline. Every action routes through `_client.executeAction(name, args)`, which splits `name` on its first dot and calls `ext.exploration.<namespace>.<tool>` on that single client (`vm_service_client.dart:167`). This is the "single-host seam" — there is no concept of more than one host.

m3 generalizes the harness from one host to **N**. Concretely the brain must:

1. **Attach to N hosts at once.** Open one `VmServiceClient` per endpoint (the Flutter VM-service endpoint + the native endpoint, today; arbitrarily many tomorrow), each pinning its own isolate, each exchanging its own handshake.
2. **Merge perception fragments into one observation.** Pull each host's `get_stable_observation`, then fold them into a single typed `Observation` whose `extensions` map is the side-by-side union of every host's namespaced fragments — no conflation, because namespaces partition the identity space.
3. **Route each tool call to the owning host by namespace.** `core.*` / `router.*` → the Flutter host; `native.*` → the native host. A name whose namespace is owned by no attached host is a hard error (fail fast, never hang).
4. **Advertise the native channel in the handshake / capabilities.** The merged manifest the brain sees is the union of all hosts' namespaces + capabilities, so the model is offered `native.tap` alongside `core.tap` and context-switches **by perception** (Flutter idle ↔ the native Auth0 form lights up) — there is NO hardcoded `switchToAppContext`.

The invariant that makes the two channels watch one screen is **m4's shared device identity** (the one `udid` String threaded into both legs — `DualLaunchHandle.deviceId`); m3 trusts that and merges what each host reports.

### 1.1 Generalize to N — the resolved design choice (NOT an open fork)

The bead **recommends** generalizing to N hosts rather than special-casing two, and this spec **adopts that**. The public API, the routing table, the handshake union, and the observation merge are all defined over an arbitrary list of hosts; "two" is just the cardinality m4 hands us today. **Rationale (one line):** the namespace→host routing table, handshake union, and fragment merge are intrinsically N-ary (a `Map<namespace, host>` + a fold over a `List<host>`); special-casing two would cost the same code while foreclosing the obvious next use (drive a Flutter app + a backend Dart service at once) — and the per-host primitives (`VmServiceClient`, `ObservationPuller`) are already one-per-host, so N is free.

### Explicitly out of scope (do NOT build these here)

- **m5 — the actual Auth0 drive** (`lenny-qxx.5`): SignIn → drive the Auth0 web form → consent → callback-return → resume-on-Flutter. m3 proves the brain can attach both channels, see both fragments every turn, and route a tool to the right host. It does **not** sign in, does not script the Auth0 flow, and adds no Auth0-specific model behavior. The live dual e2e here **STOPS before SIGN IN** (mirroring m4's e2e and `native_host_e2e_test.dart`).
- **Android** — the native host is `--platform ios` only (mirrors m4 / `AppiumBackend`). No Android attach path.
- **New backends** (`lenny-qxx.6`): `PatrolBackend` / `XcuitestBackend` / `PlatformChannelBackend`. m3 attaches to whatever speaks `ext.exploration.*`; it is backend-agnostic by construction and takes no dependency on `AppiumBackend`.
- **Any change to the per-process launch lifecycle.** m4 owns boot/hold/teardown of the two processes and produces `DualLaunchHandle`. m3 does not touch `launcher.dart`'s spawn/teardown; it only **reads** the two endpoints off the handle (or off m4's `vm_service_ready` JSON / `--uri-file`).
- **`leonard_cli --launch` autonomous native loop.** The dual path is exposed through `leonard_drive` (the external-brain front door, per m4 §6) and through the new multi-host `MultiHostSession` API. Wiring lenny's OWN autonomous LLM loop to dual-attach is left for m5 (it needs the Auth0 goal to be worth anything).
- **Per-host contract-version surfacing & version-equality gating** (see §3) — deferred. Both lenny hosts ship contract version `"2"` today, so the merge stamps the primary version and tolerates divergence.
- **Partial-host recovery** (see §4.3) — a transport loss on any channel terminates the session, single-host parity.

---

## 2. The Public API composition shape (THE one human-review fork — flagged, not resolved)

This is the single decision this spec leaves open for human review. Everything downstream of it — routing (§4), the handshake union (§3), the observation merge (§5), and every AC — is **identical** regardless of which composition wins, so it is low-stakes; the fork is purely internal plumbing. (Framed the same way m4-spec §2 framed the `--boot-sim` default.)

**The two shapes:**

- **(A) RECOMMENDED — a new `MultiHostSession` façade over N per-host `_HostChannel`s.** Each `_HostChannel` is the per-host bundle `{VmServiceClient client, ObservationPuller puller, HandshakeResult handshake}` — i.e. exactly the per-session state the single-host `LeonardSession` holds, but one per attached host. The single-host `LeonardSession` stays **byte-for-byte** unchanged.
- **(B) a thin wrapper holding `List<LeonardSession>`** that re-merges each child session's public outputs.

**RECOMMENDATION: shape (A).** Reasons:

1. **Single per-host primitive.** `_HostChannel` is the minimal per-host unit — one client, one puller, one handshake — which is exactly the state `LeonardSession` already holds for N=1. Lifting that to `List<_HostChannel>` is the smallest generalization and keeps the single-host class as the literal N=1 reference.
2. **No N `LeonardSession` lifecycles to coordinate.** Wrapping N full `LeonardSession`s (shape B) would duplicate N progress streams, N turn-event streams, and N diff baselines that the wrapper must then re-merge — pure overhead. A façade over N `_HostChannel`s coordinates N independent VM-service latches directly (the terminal-latch / handshake reset is per-VM-service-endpoint, not per-`LeonardSession`-object).
3. **`LeonardSession` stays byte-for-byte single-host.** Shape (A) leaves `LeonardSession` untouched except for `implements SessionSurface` + a one-line `executeAction` forwarder (§4.4) — preserving AC1.

> **This is the ONE human-review fork.** If the reviewer prefers shape (B) (a thin `MultiHostSession` that literally holds `List<LeonardSession>` and re-merges their public outputs), the routing/merge rules in §3–§5 and all ACs are **identical** — only the internal composition differs, and the merge reads from each child session's public `handshake`/`observe` instead of from a `_HostChannel`. Everything downstream of §2 is independent of which composition wins. **Switch by changing the internal field type; nothing else in this spec changes.**

The remainder of this spec is written against shape (A) (the recommendation) for concreteness.

### 2.1 The N-host attach entrypoint

`MultiHostSession` mirrors `LeonardSession`'s two construction modes (owning vs borrowed), generalized to N:

```dart
// lib/src/multi_host/multi_host_session.dart  (NEW)

/// One attached host: the namespaces it owns + the channel to reach it.
/// `namespaces` is captured from the host's handshake at start().
class HostAttachment {            // exported (callers name endpoints)
  const HostAttachment({required this.label, required this.uri});
  final String label;            // e.g. 'flutter' / 'native' — diagnostics only
  final Uri uri;                 // ws://…/ws
}

class MultiHostSession implements SessionSurface {
  MultiHostSession._(this._channels);

  /// Owning attach: open one VmServiceClient per [hosts] endpoint (each
  /// pins its own first isolate), in the order given. CLI-only (routes
  /// through `package:vm_service/vm_service_io.dart` → dart:io), exactly
  /// like LeonardSession.connect. Call [start] before observe/act.
  static Future<MultiHostSession> connectAll(List<HostAttachment> hosts);

  /// Borrowed attach (web-safe / DevTools): wrap already-connected
  /// (VmService, isolateId) pairs. Mirrors LeonardSession.fromVmService;
  /// each channel's client is BORROWED so end() never tears down a
  /// connection it did not open.
  factory MultiHostSession.fromVmServices(
    List<({String label, VmService vm, String isolateId})> hosts,
  );

  @visibleForTesting
  factory MultiHostSession.forTest(List<VmServiceClient> clients);
}
```

`connectAll` is the multi-host analogue of `LeonardSession.connect`; the dual case is just `connectAll([HostAttachment(label:'flutter', uri:flutterWsUri), HostAttachment(label:'native', uri:nativeEndpoint)])`. Ownership is **per channel** (each `_HostChannel.client` carries its own `ownsConnection` exactly as `VmServiceClient` already does), so a borrowed Flutter channel (DevTools) + an owned native channel dispose independently — `end()` disposes each channel's client, and each `VmServiceClient.dispose()` already no-ops on a borrowed connection.

---

## 3. Handshake Merge (union across N hosts)

`MultiHostSession.start(goal, config)` performs, per channel, the SAME handshake the single-host path does — `await channel.client.handshake()` (`ext.exploration.core.handshake`, `vm_service_client.dart:108`), storing each `HandshakeResult` on its `_HostChannel`. The decoded shape is `HandshakeResult{String contractVersion, List<ExtensionManifestEntry> extensions, List<String> capabilities}` and `ExtensionManifestEntry{String namespace, List<String> tools}` (`types.dart:5,29`). Then it builds **one merged `HandshakeResult`** and a **namespace→channel routing table** (§4):

- **Namespace union.** Collect every `ExtensionManifestEntry` from every channel's `handshake.extensions`, preserving each entry's bare-tool list, into one flat `List<ExtensionManifestEntry>` that the merged `handshake.extensions` exposes. Order: channels in attach order, entries in handshake order (deterministic for the manifest/header).
- **Capability union — de-duplicated, FIRST-SEEN (wire) order, NOT sorted.** Concatenate all channels' `handshake.capabilities` in attach order, then de-duplicate keeping the first occurrence of each string. The result preserves wire order to **match the existing single-host emission**: `vm_service_client.dart:141-146` decodes capabilities with a plain in-order append (no sort), and `leonard_drive.dart:206` emits `session.handshake.capabilities` verbatim. So `screenshot`, reported by the Flutter host, appears **exactly once** even if multiple hosts report it, and the merged `capabilities` shape is byte-compatible with what `drive tools` already prints.
- **Contract version — the PRIMARY (Flutter, first) channel's version, stamped onto every record.** The merged `HandshakeResult.contractVersion` is set to the **primary (first/Flutter) channel's** `contractVersion`. `bringUpSession` (`session_bringup.dart:54-74`) walks `session.handshake.extensions` and stamps **every** `ExtensionManifestRecord` — including `native` — with `session.handshake.contractVersion`, i.e. the merged/primary version. This is a **documented limitation for m3**: per-host versions are NOT surfaced separately in the bring-up manifest. **No version-equality gate in m3** (see §7 risk note): hosts are independent processes that may legitimately ship different contract versions; the merge is tolerant. A major-version incompatibility is a future hardening (`lenny-qxx.6`-adjacent), not m3 scope.

  > **Deferred clean fix (one line):** per-namespace versioning — a `contractVersionFor(namespace)` accessor on the merged `HandshakeResult`, consumed by `bringUpSession` to stamp each `ExtensionManifestRecord` with its own host's version. Acceptable to defer today because **both lenny hosts ship the same contract version (`"2"`)** — verified by `vm_service_client_test.dart:68` (`expect(result.contractVersion, equals('2'))`) and `binding_e2e_integration_test.dart:128` (`expect(h.contractVersion, '2')`). There is no existing `contractVersionFor` accessor.

**The `native` channel is thereby advertised:** because the native host's handshake reports the `native` namespace (and its bare tools `tap`/`enter_text`/`press`/`swipe`), the union puts `native` into `handshake.extensions`. The existing brain-side projection then offers them to the model: `buildExtensionTools(requested: {...args.extensions, 'core', 'native'}, handshake: mergedHandshake.extensions)` emits `native.tap` etc. as `ToolDescriptor`s (`extension_tools.dart`), and `DefaultLoopHost.mergedTools()` surfaces them every turn.

### 3.1 Namespace-collision policy (resolved)

Two attached hosts each owning the SAME namespace is **ambiguous** (which host receives `ns.tool`?). By design this never happens — `core`/`router`/`riverpod`/`dio` are Flutter-host-only and `native` is native-host-only — but the merge MUST detect it, not silently shadow:

- **Hard error at `start()`** (fail fast, before the loop runs): if any namespace appears in more than one channel's handshake, `MultiHostSession.start` throws `MultiHostNamespaceCollision(namespace, [labelA, labelB])` (new error type, exported via the barrel). This is a configuration error (two hosts claiming `core`), surfaced once at attach rather than as a silent wrong-host dispatch mid-session.
- **`core` is the canonical example:** the native host is a pure-Dart `ExplorationHost` and reports namespace `native` (not `core`) in its handshake; the Flutter host reports `core`. They do not collide. *However*, BOTH hosts expose the raw `ext.exploration.core.handshake` and `ext.exploration.core.get_stable_observation` VM extensions (that is the shared host surface, NOT a `core` *namespace entry* in the manifest). The collision check operates on **manifest namespaces** (`handshake.extensions[].namespace`), where the native host reports only `native` — so there is no false positive. (Confirmed: the native host's `ExplorationHost` manifest carries the `NativeExtension` whose `namespace => 'native'` — `native_extension.dart:36`; it does not register a `core` `ExtensionManifestEntry`.)

---

## 4. Tool Routing (`ns.tool` → owning host)

### 4.1 The routing table

At `start()`, after the collision check, `MultiHostSession` builds `Map<String, _HostChannel> _route` mapping every namespace in the merged manifest to the channel whose handshake reported it. `core` and any other Flutter namespaces → the Flutter channel; `native` → the native channel.

### 4.2 `executeAction` / `act`

`MultiHostSession.executeAction(name, args)` (and `act({name, args})`, the same marshalling `LeonardSession.act` does at `session.dart:182`) parses the namespace off `name` and dispatches to the owning channel's client:

```dart
Future<Map<String, dynamic>> executeAction(String name, Map<String, dynamic> args) {
  final int dot = name.indexOf('.');
  if (dot <= 0 || dot == name.length - 1) {
    throw ArgumentError.value(name, 'name',
        'action name must be qualified as <namespace>.<tool>');   // matches VmServiceClient
  }
  final String ns = name.substring(0, dot);
  final _HostChannel? ch = _route[ns];
  if (ch == null) {
    throw MultiHostUnknownNamespace(ns, _route.keys.toList()..sort());  // fail fast
  }
  return ch.client.executeAction(name, args);   // reuse the SAME per-host dispatch
}
```

- **Owning host found → reuse the existing per-host dispatch verbatim.** `VmServiceClient.executeAction` (`vm_service_client.dart:167`) already splits `name` and calls `ext.exploration.<ns>.<tool>` on its pinned isolate, JSON-encoding each arg value (the existing wire contract). m3 does not re-implement dispatch; it only **selects** the client.
- **Unknown / unmapped namespace → hard error** (`MultiHostUnknownNamespace`, exported). This catches a model hallucinating a namespace, or attaching to fewer hosts than the manifest implies. It is thrown synchronously before any wire call — the loop never hangs on an unroutable name. (`DefaultLoopHost._callTransport` only wraps transport `RPCError`/`StateError`; an `ArgumentError`/`MultiHostUnknownNamespace` propagates as a normal harness error, the same class as today's malformed-name `ArgumentError`.)
- **Tool-name parsing contract is unchanged:** namespace is everything before the **first** dot; the tool token is the remainder (which may itself contain dots, e.g. `core.screenshot` stays one tool). Identical to `VmServiceClient` (`vm_service_client.dart:171-177`) — no two-dot special handling, no new grammar.

### 4.3 Per-host action-failure isolation

Auto-disable stays **per namespace**, which is already per-host because each namespace maps to exactly one channel. `MultiHostSession.disableExtension(namespace, reason)` records the namespace in a session-wide `_disabled` set (mirroring `LeonardSession._disabled`) and the routing table is unaffected (disable hides tools from `mergedTools`, it does not unmap the route). If `native` strikes out (3 observation failures, per `LoopDriver._accountExtensionStrikes`), only the `native` namespace is disabled; `core`/Flutter tools stay active. A transport loss on ONE channel surfaces as `VmServiceConnectionLost` and terminates the session (same as single-host) — m3 does NOT attempt partial-host recovery (deferred; see §7 risks).

### 4.4 Adapting into the existing loop (`DefaultLoopHost`)

`DefaultLoopHost.fromSession` is typed against `LeonardSession` (`default_loop_host.dart:57`) and reaches into `_session.handshake`, `_session.pullObservation`, `_session.disableExtension`, and — for actions — `_session.client.executeAction` (`default_loop_host.dart:131`). Note `LeonardSession.client` is `@internal` (`session.dart:145-146`) and `SessionSurface` does NOT expose it; the loop must call a routed `executeAction` on the interface instead. The brain-loop change is therefore four moves, not just widened param types:

```dart
// lib/src/loop_driver/session_surface.dart  (NEW — pure, io-free)
abstract class SessionSurface {
  HandshakeResult get handshake;                       // merged for MultiHost
  Future<Observation> pullObservation({StabilityPolicy policy});  // merged
  Future<Map<String, dynamic>> executeAction(String tool, Map<String, dynamic> args); // routed
  void disableExtension(String namespace, String reason);
}
```

1. **Extract the interface** `SessionSurface { handshake; pullObservation; executeAction; disableExtension }` (above).
2. **`LeonardSession implements SessionSurface`** — `handshake` (`session.dart:104`), `pullObservation` (`session.dart:153`), and `disableExtension` (`session.dart:211`) already exist; **add a one-line `executeAction(tool, args) => _client.executeAction(tool, args)` forwarder** (`LeonardSession` has no public `executeAction` today — only `act` at `session.dart:182` and the `@internal client`). This forwarder is a no-behavior-change.
3. **`MultiHostSession implements SessionSurface`** with the merged/routed implementations.
4. **Widen `DefaultLoopHost.fromSession`'s `session` param AND the stored `_session` field from `LeonardSession` to `SessionSurface`, AND change the `executeAction` body** from `_session.client.executeAction(tool, args)` (`default_loop_host.dart:131`) to `_session.executeAction(tool, args)` (routed via the interface, no longer reaching `client`). Likewise `bringUpSession` (`session_bringup.dart:54`) widens its `session` param to `SessionSurface`.

This is the entire brain-loop change: **one interface + two `implements` + widened params (host + bring-up) + ONE `executeAction` body edit in `default_loop_host.dart`.** It is source-compatible for every existing caller (a `LeonardSession` still passes). The 10-step `LoopDriver` is **untouched**.

---

## 5. Observation Merge (N fragments → one `Observation`, side-by-side)

### 5.1 The merge model (resolved)

Each host's `get_stable_observation` returns a wire bundle that `Observation.fromJson` decodes into `Observation{core, extensions, stability, screenshot?}` (`observation/models.dart`). The Flutter host populates `core` (semantics tree, route stack, errors) and any Flutter `extensions` (`router`/`riverpod`/`dio`); the **native host is a pure-Dart `ExplorationHost`** whose `core` is **empty** (no Flutter semantics) and whose `extensions['native']` carries the `NativePerception` fragment.

`MultiHostSession.observe(policy)` pulls each channel's observation (via that channel's `ObservationPuller`, the SAME `pull()` path) and **folds them into one merged `Observation`**:

- **`core`** ← the **Flutter (primary) channel's** `core` fragment. (The native host contributes no Flutter semantics; its `core` is empty.) This keeps `CoreFragment` semantically "the Flutter UI tree", which `ObservationDiffer._coreDiff` and the renderer already assume. Generalization note: if multiple hosts ever populated `core`, the merge takes the FIRST non-empty `core` in attach order — but with today's hosts only Flutter does, so this is unambiguous.
- **`extensions`** ← the **union of every channel's `extensions` map**, keyed by namespace. Because namespaces are collision-checked at `start()` (§3.1), the union is conflict-free: `extensions['router']`, `extensions['dio']` (Flutter) sit side-by-side with `extensions['native']` (native). No key is overwritten; no fragment is conflated. This is exactly the "namespaced, side-by-side" shape `ExtensionFragment`/`ObservationDiffer._extensionsDiff` already diff per-namespace, so the merged observation diffs correctly with **zero differ changes** (the differ walks `extensions` by key; a new `native` key is just an added/changed fragment like any other).
- **`stability`** ← merged with the framework-level fields taken from the PRIMARY (Flutter) channel **verbatim**, and only `extensionsBusy` concatenated across hosts. `StabilityMetadata` (`observation/models.dart:488`) is `{String policy, String terminatedBy, int durationMs, Map<String,dynamic> frameworkBusy, List<ExtensionBusy> extensionsBusy}`. Therefore the merge takes `policy`, `terminatedBy`, `durationMs`, **and `frameworkBusy` (a `Map<String,dynamic>`, line 532 — NOT a bool or list)** from the primary channel verbatim, and **concatenates `extensionsBusy`** (a `List<ExtensionBusy>`, line 533 — each entry already namespaced via `ExtensionBusy.namespace`, line 464) across all hosts. The native host's busy signal therefore **rides `extensionsBusy`**: its busy entries appear alongside Flutter's in the concatenated list. There is **no `frameworkBusy`-union** semantic — `frameworkBusy` is a framework-level map sourced solely from the primary channel.
- **`screenshot`** ← the **primary (Flutter) channel's** `screenshot` when present (the native host does not expose `core.screenshot`). Single screenshot, single vision payload — no dual-image ambiguity in m3. (If the native channel ever exposes a screenshot capability, picking among them is deferred; not in m3 scope.)

The merge is a pure function `mergeObservations(List<Observation> perHost) → Observation` in `lib/src/multi_host/observation_merge.dart` (NEW, pure, io-free) — directly unit-testable on hand-built `Observation`s, no VM service.

### 5.2 Diff baseline & `observeWithDiff`

`MultiHostSession` keeps ONE `_prevObservation` baseline against the **merged** observation (mirroring `LeonardSession._prevObservation`). Because `ObservationDiffer.diff(prev, curr)` already diffs `core` and `extensions` **per-key** (`observation_differ.dart`), diffing two merged observations yields correct per-fragment deltas (Flutter `core` change here, `native` fragment change there) with no per-host bookkeeping. m3 does **not** need a per-host differ — the merge places each host's fragment under its own namespace and the existing structural differ does the rest. (`DefaultLoopHost.observe()` calls `pullObservation` and the driver owns its own `_prev`; the merged observation flows through unchanged.)

### 5.3 Stability policy across hosts (resolved)

`observe(policy)` applies the **same** `StabilityPolicy` to **every** channel and returns only when **all** channels have produced their stable observation — i.e. the per-host `pull()`s run concurrently (`await Future.wait`) and the merge happens once all resolve. Semantics: "stable" means **all hosts idle** under the requested policy (the union interpretation), which is the correct context-switch signal — the brain should observe once Flutter has settled AND the native side has settled, so it sees the true joint state. Latency skew (native Appium round-trips are slower than Flutter VM-service) is absorbed by `Future.wait`; the slowest host gates the turn, which is the intended "wait for the whole screen to settle" behavior. (No per-host policy divergence in m3 — one policy, all hosts, join on all. `StabilityPolicy` enum: `observation_puller.dart:22`.)

### 5.4 Context-switch is the model's job (design intent, load-bearing)

The merged observation carries **both** fragments **every turn**: the Flutter `core`/`extensions` AND `extensions['native']`. When the Flutter app sits idle on a "Sign in" button its `core` is quiet and the live signal is in `extensions['native']` (the Auth0 web form's accessibility tree); when control returns to Flutter the `native` fragment goes quiet and `core` lights up. The model reads both and **acts where the live one is** — it picks `native.tap` vs `core.tap` from the merged tool list by what it perceives. There is **no** `switchToAppContext`, no host-focus flag, no harness-side mode. The harness's only job is to present both fragments truthfully and route the chosen tool; the switching is emergent from perception. This is the "one genuinely new agent capability" the bead names.

---

## 6. `leonard_drive` Consumption of m4's Two Endpoints (m3 scope only)

m4 produces `DualLaunchHandle{flutterWsUri, nativeEndpoint, deviceId}` (`launcher.dart:328`) and emits one `vm_service_ready` JSON line carrying `flutter_ws_uri` + `native_endpoint` + `device_id` (and a two-line `--uri-file`, flutter-first). m3 adds the **consumer** side: an external brain (or a thin built-in driver) that attaches a `MultiHostSession` to **both** endpoints, merges, and routes — **as far as attach/merge/route only**. Auth0 sign-in is m5.

m3 adds a `leonard_drive` subcommand **`drive-dual`** (new; the existing single-host `tools`/`observe`/`invoke`/`screenshot`/`up`/`down` — `leonard_drive.dart:150-156`, including the m4 dual `up`/`_upDual` at line 444 — are untouched) that demonstrates the multi-host attach end to end against an `up`-held dual session:

- Inputs: `--flutter-uri <ws>` + `--native-uri <ws>` (or `--uri-file <F>` to read both lines flutter-first), the symmetric inverse of m4's handoff. Reuses the existing `--policy`, `--tool`, `--args` flags.
- `drive-dual tools` → `MultiHostSession.connectAll([flutter, native]).start()`, then print the **merged** manifest in the SAME shape `tools` already prints (`leonard_drive.dart:197-207`): `{contract_version, namespaces:[{namespace, tools:[…]}…], capabilities:[…]}`. Proves the union (§3) and that `native` is advertised (job 4).
- `drive-dual observe` → print the **merged** `Observation.toJson()` — one JSON with `core` (Flutter) + `extensions.native` (native) side by side. Proves the merge (§5).
- `drive-dual invoke --tool native.tap --args '{"label":"Email address"}'` → routed to the native channel; `--tool core.tap …` → routed to Flutter. Proves routing (§4). An unknown namespace prints the `MultiHostUnknownNamespace` error and exits 1.

`leonard_drive` stays the thin, stateless, **no-model** external-brain front door (m4 §6 framing): `drive-dual` does attach + one operation + print + disconnect, exactly like the single-host subcommands but over two channels. **It makes no Auth0 calls and runs no LLM loop** — that is m5. All `dart:io`/launcher consumption stays in `leonard_cli`; the multi-host attach/merge/route logic it calls lives in `leonard_agent` and is io-free.

> **Scope fence:** `drive-dual` is the *minimal* consumer that exercises m3's three jobs against a live dual session. It is NOT the autonomous loop and NOT the Auth0 driver. If a reviewer wants only the library API + tests (no new subcommand), `drive-dual` can be dropped without affecting §2–§5 — but it is the cheapest live proof that the merged session is well-formed, so it is included.

---

## 7. Acceptance Criteria

Each is independently verifiable; the HOW is named. Tiers (§9): **T1** = unit/wiring (default `melos run test`, fakes — no real VM service / device); **T2** = live dogfood (hardware-gated, **self-skips** when env/Appium absent — env gate is synchronous at `main()`, async reachability probe inside the test body, mirroring m4/m2).

1. **Single-host attach is unchanged (back-compat).** `LeonardSession.connect/start/observe/observeWithDiff/act/run/end` and `leonard_drive` single-host `tools`/`observe`/`invoke` behave exactly as today. *Check (T1):* the existing `leonard_agent` session tests and `leonard_drive` tests pass **unmodified**, and these VERIFIED callers compile unchanged against a `LeonardSession` (the param/field widenings are source-compatible): `leonard_cli/lib/src/run.dart` (`LeonardSession.connect` at line 156 → `bringUpSession(...)` at line 206 → `session.run(...)` at line 225); `leonard_devtools/.../prompt_panel_controller.dart` (`DefaultLoopHost.fromSession(...)` at line 142 then `session.run(host: …)` at line 156); the single-host `leonard_drive` path; and all tests. `LeonardSession`'s public surface is byte-for-byte (no signature change beyond `implements SessionSurface` + the one-line `executeAction` forwarder, which adds a member every caller could already reach via `act`/`client`).

2. **`MultiHostSession.connectAll` attaches N channels, each pinning its own isolate.** *Check (T1, `multi_host_session_test.dart`):* `MultiHostSession.forTest([fakeClientA, fakeClientB])`; assert two `_HostChannel`s, each routing `executeAction` to its OWN fake client (a `core.*` call lands on client A, a `native.*` call lands on client B), and `end()` disposes each client exactly once (borrowed clients no-op, owned dispose — assert via the fake's recorded `dispose` + `ownsConnection`).

3. **Handshake union merges namespaces + de-dupes capabilities (first-seen wire order) across hosts.** *Check (T1, `multi_host_handshake_test.dart`):* two fake handshakes — `{core, router, capabilities:[screenshot]}` and `{native, capabilities:[]}`; assert the merged `handshake.extensions` contains all three namespaces (with each entry's bare tools intact) and `handshake.capabilities == [screenshot]` — **union, de-duped, FIRST-SEEN order (NOT sorted)**, `screenshot` appearing exactly once, the shape matching `drive tools`' `capabilities` emission (`leonard_drive.dart:206` + decode order `vm_service_client.dart:141-146`). Assert `buildExtensionTools(requested:{core,router,native}, handshake: merged.extensions)` emits `core.*`, `router.*`, AND `native.tap`/`native.enter_text`/`native.press`/`native.swipe` descriptors.

4. **The `native` channel is advertised in the merged manifest.** *Check (T1, same file):* with a native fake handshake reporting `native` + its four tools, the merged manifest's `namespaces` includes `{namespace:'native', tools:[tap, enter_text, press, swipe]}`. *Check (T2):* `drive-dual tools` against a live dual session prints `native` among `namespaces` and the union of capabilities.

5. **Tool routing dispatches `ns.tool` to the owning host.** *Check (T1, `multi_host_routing_test.dart`):* route table `{core→A, router→A, native→B}`; assert `executeAction('core.tap', …)` and `executeAction('router.go', …)` hit fake A and `executeAction('native.tap', …)` hits fake B, each with the fully-qualified name + args forwarded verbatim (the per-host `VmServiceClient.executeAction` wire shape is reused unchanged).

6. **Unknown / unmapped namespace is a hard error (fail fast, no hang).** *Check (T1, same file):* `executeAction('ghost.do', …)` throws `MultiHostUnknownNamespace` synchronously (before any wire call), naming `ghost` and listing the known namespaces; `executeAction('bare', …)` and `executeAction('core.', …)` throw `ArgumentError` (the existing malformed-name contract, matching `vm_service_client.dart:171-177`). No fake client receives the call.

7. **Namespace collision across hosts is detected at start().** *Check (T1, `multi_host_handshake_test.dart`):* two fake handshakes both reporting `core`; assert `start()` throws `MultiHostNamespaceCollision` naming `core` and both host labels, BEFORE the loop / before any observation. (Proves §3.1 — no silent shadowing.)

8. **Observation merge places N fragments side-by-side; framework fields from primary, `extensionsBusy` concatenated.** *Check (T1, `observation_merge_test.dart`, pure):* `mergeObservations([flutterObs, nativeObs])` where `flutterObs.core` has semantics nodes + `extensions={router}` + `stability` with `frameworkBusy:{…}` and one `ExtensionBusy(namespace:'router')`, and `nativeObs.core` is empty + `extensions={native}` + `stability` with one `ExtensionBusy(namespace:'native')`; assert: merged `core` == the Flutter `core`; merged `extensions` has BOTH `router` and `native` keys (neither overwritten); `stability.frameworkBusy`/`policy`/`terminatedBy`/`durationMs` are the PRIMARY (Flutter) values **verbatim** (NOT unioned); `stability.extensionsBusy` is the **concatenation** of both hosts' lists (the `native` busy entry appears alongside the Flutter `router` one, each already namespaced via `ExtensionBusy.namespace`); and `screenshot` is the Flutter one. Round-trip `merged.toJson()` and assert both extension fragments present.

9. **Merged observation diffs per-fragment with the existing differ.** *Check (T1, same file):* `ObservationDiffer.diff(merged0, merged1)` where only `extensions['native']` changed (Flutter `core` identical); assert the diff reports the `native` extension delta and an empty/no-op `core` diff — proving the unchanged differ handles the merged shape (no per-host differ needed).

10. **`observe(policy)` applies one policy to all hosts and joins on all.** *Check (T1, `multi_host_observe_test.dart`):* two fake pullers, one slow; assert `observe(boundedStability)` calls `pull(policy: boundedStability)` on BOTH and returns only after both resolve (the merged result reflects both), and `observeWithDiff` advances the single merged `_prevObservation` baseline.

11. **`DefaultLoopHost` drives a `MultiHostSession` unchanged via `SessionSurface`.** *Check (T1, `multi_host_loop_host_test.dart`):* `DefaultLoopHost.fromSession(session: aMultiHostSession, …)` (a `SessionSurface`); assert `mergedTools()` includes `native.*`, `observe()` returns the merged observation, and `executeAction('native.tap', …)` routes to the native fake — i.e. the loop host needs no MultiHost-specific code beyond the widened param type + the one `executeAction` body edit (now `_session.executeAction`, not `_session.client.executeAction`). A `LeonardSession` still satisfies the same `fromSession` call (compile + run).

12. **`leonard_drive drive-dual` attaches, merges, and routes against a LIVE dual session.** *Check (T2, `drive_dual_e2e_test.dart`, hardware-gated, self-skips):* `up` the native dual path (reusing m4's `up`/`_upDual`), capture `flutter_ws_uri` + `native_endpoint`; run `drive-dual tools` (assert merged manifest has `core` AND `native`), `drive-dual observe` (assert merged JSON has `core` + `extensions.native`), `drive-dual invoke --tool native.tap …` (assert routed to the native channel and `{ok:true|false}` returned). **STOP before SIGN IN** (m5 owns Auth0). Self-skips when `LEONARD_NATIVE_SIM_UDID` / `LEONARD_NATIVE_APP` absent or Appium unreachable.

13. **`feat/leonard-native` base; `leonard_agent` stays Flutter- and io-free.** *Check (T1):* `tool/check_no_dart_io.dart` (the existing CI guard) is clean — the new `multi_host/` + `session_surface.dart` files import no `dart:io` and no Flutter; the `MultiHostSession.connectAll` owning path routes through `VmServiceClient.connect` (the existing single `vm_service_io.dart` seam), adding no new `dart:io` import to `lib/`. `melos run analyze` + `melos run format` clean.

---

## 8. Implementation Plan (file-by-file, ordered)

### `packages/leonard_agent` (the harness — pure, io-free)

1. **`lib/src/loop_driver/session_surface.dart`** (NEW) — extract `abstract class SessionSurface { handshake; pullObservation; executeAction; disableExtension; }` (§4.4). Pure.
2. **`lib/src/session.dart`** — declare `class LeonardSession implements SessionSurface`. Add a one-line `executeAction(tool, args) => _client.executeAction(tool, args)` forwarder (no behavior change; `pullObservation`/`disableExtension`/`handshake` already exist — lines 153/211/104; there is no public `executeAction` today). **No other change** (AC1).
3. **`lib/src/multi_host/observation_merge.dart`** (NEW) — pure `Observation mergeObservations(List<Observation> perHost)` (§5.1): primary `core`/`screenshot`; unioned `extensions`; merged `stability` taking `policy`/`terminatedBy`/`durationMs`/`frameworkBusy` from the primary verbatim and **concatenating** `extensionsBusy`. Throws nothing (collision is caught earlier at handshake); assumes namespace-disjoint inputs.
4. **`lib/src/multi_host/multi_host_errors.dart`** (NEW) — `MultiHostNamespaceCollision`, `MultiHostUnknownNamespace` (both carry the offending namespace + context; `toString` actionable).
5. **`lib/src/multi_host/multi_host_session.dart`** (NEW) — `HostAttachment`, the private `_HostChannel{client, puller, handshake}`, and `MultiHostSession implements SessionSurface`:
   - `connectAll(List<HostAttachment>)` — `Future.wait` of `VmServiceClient.connect(uri)` per host (owning), build channels; `fromVmServices(...)` (borrowed); `forTest(List<VmServiceClient>)`.
   - `start(goal, config)` — per-channel `client.handshake()`; run the §3.1 collision check (throw `MultiHostNamespaceCollision`); build the merged `HandshakeResult` (§3: union `extensions`; de-dupe `capabilities` first-seen; `contractVersion` = primary) and `Map<String,_HostChannel> _route` (§4.1); emit `SessionStarted` on `progress` (reuse the same `SessionProgressEvent` types — `types.dart:58`).
   - `handshake` getter → the merged result (`StateError` before `start`, mirroring `LeonardSession`).
   - `observe({policy})` / `pullObservation({policy})` — `Future.wait` of per-channel `puller.pull(policy)`; `mergeObservations(...)` (§5.1/§5.3). `observeWithDiff` — diff merged vs the single `_prevObservation`.
   - `executeAction(name, args)` / `act({name, args})` — route per §4.2 (`MultiHostUnknownNamespace` on miss; `ArgumentError` on malformed name).
   - `disableExtension(ns, reason)` — record in `_disabled`, emit `ExtensionAutoDisabled` (§4.3).
   - `end()` — dispose every channel's client (each `VmServiceClient.dispose` no-ops on borrowed), close `progress`/`turnEvents`.
   - `run({host, provider, writer, …})` — mirror `LeonardSession.run` (build a `LoopDriver` over the supplied `DefaultLoopHost`), so the autonomous path can drive a multi-host session in m5 without rework. (Convenience; the loop driver is unchanged.)
6. **`lib/src/loop_driver/default_loop_host.dart`** — widen `fromSession({required SessionSurface session, …})` from `LeonardSession` (line 57); change the `_session` field type to `SessionSurface` (line 74); `observe()` keeps `_session.pullObservation` (line 123); **change `executeAction()`'s body from `_session.client.executeAction(tool, args)` (line 131) to `_session.executeAction(tool, args)`** (routed via the interface — `client` is `@internal` and not on `SessionSurface`). Source-compatible for the existing `LeonardSession` caller.
7. **`lib/src/session_bringup.dart`** — widen `bringUpSession({required SessionSurface session, …})` (line 54); `session.handshake.extensions` reads the merged manifest for a `MultiHostSession`, the single one for a `LeonardSession`. Each `ExtensionManifestRecord` is stamped with `session.handshake.contractVersion` (lines 71-74) — the merged/primary version, the documented m3 limitation (§3). No other change.
8. **`lib/leonard_agent.dart`** (barrel) — export `MultiHostSession`, `HostAttachment`, `SessionSurface`, `MultiHostNamespaceCollision`, `MultiHostUnknownNamespace`, and `mergeObservations` (for the e2e/tests). Keep `LeonardSession`, `VmServiceClient`, etc. exported as today.

### `packages/leonard_cli` (the external-brain front door — owns dart:io)

9. **`bin/leonard_drive.dart`** — add the `drive-dual` subcommand (§6): `--flutter-uri`/`--native-uri` (or `--uri-file`), dispatch to a new `_driveDual(res)` that `MultiHostSession.connectAll([...]).start()`, runs one of `tools`/`observe`/`invoke` over the merged session, `_emit`s JSON (the `tools` case mirrors the existing `{contract_version, namespaces, capabilities}` shape at lines 197-207), and `end()`s in `finally`. The existing single-host commands and `up`/`down` (incl. the m4 dual `up`/`_upDual`) are untouched. Add `drive-dual` to the allowed-command set (lines 150-156) and update `_usage()`.

### Tests (taxonomy: stubbed/fake = unit; live device = e2e — the house rule)

10. **`packages/leonard_agent/test/multi_host/multi_host_session_test.dart`** (NEW, T1) — AC2 (attach, per-client dispatch, dispose/ownership).
11. **`packages/leonard_agent/test/multi_host/multi_host_handshake_test.dart`** (NEW, T1) — AC3, AC4, AC7 (union + first-seen-order capabilities, advertise native, collision).
12. **`packages/leonard_agent/test/multi_host/multi_host_routing_test.dart`** (NEW, T1) — AC5, AC6 (route to owner, unknown/malformed errors).
13. **`packages/leonard_agent/test/multi_host/observation_merge_test.dart`** (NEW, T1) — AC8, AC9 (pure merge: primary framework fields + concatenated `extensionsBusy` + differ).
14. **`packages/leonard_agent/test/multi_host/multi_host_observe_test.dart`** (NEW, T1) — AC10 (one policy, join-on-all, single merged baseline).
15. **`packages/leonard_agent/test/multi_host/multi_host_loop_host_test.dart`** (NEW, T1) — AC11 (`DefaultLoopHost` over `SessionSurface`; both session types satisfy `fromSession`; routed `executeAction`).
16. **`packages/leonard_cli/test/drive_dual_e2e_test.dart`** (NEW, T2) — AC12, live dual attach/merge/route, hardware-gated + self-skipping, STOP before sign-in.

**Load-bearing constraints (carry from m4 / project rules):**
- `leonard_agent` must stay Flutter- and `dart:io`-free — the `multi_host/` files use only `package:vm_service` (via the existing `VmServiceClient` seam) + pure Dart. No `launcher`/process imports leak upward. (`tool/check_no_dart_io.dart` guards it — AC13.)
- Reuse the per-host primitives verbatim: `VmServiceClient` (one per channel, ownership per channel), `ObservationPuller`, `HandshakeResult`, `buildExtensionTools`, `ObservationDiffer`, `DefaultLoopHost`, `LoopDriver`. m3 adds the **fold/route layer above them**, not new dispatch/observe/diff machinery.
- The single-host `LeonardSession` path is the literal N=1 reference and stays byte-for-byte (AC1) — except `implements SessionSurface` + the one-line `executeAction` forwarder.

---

## 9. Validation Plan

Exactly **two tiers**, mirroring the package convention and the **test-taxonomy house rule** (a test that fakes the VM service / device is **unit/wiring**, NOT e2e; never name a faked-attach file `*_e2e_test.dart`).

### Tier 1 — UNIT / wiring (fakes; runs in default `melos run test`)

The merge, union, collision, routing, and join-on-all logic is exercised entirely on **fakes** — fake `VmServiceClient`s (record `executeAction`/`handshake`/`dispose` calls), fake `ObservationPuller`s (canned `Observation`s), and hand-built `HandshakeResult`/`Observation` values. No real VM service, no device, no Appium. Covers AC1–AC11, AC13. The pure `mergeObservations`/`ObservationDiffer` paths (AC8/AC9) need no fakes at all — direct value-in/value-out.

### Tier 2 — LIVE dogfood dual e2e (hardware-gated, self-skips)

`packages/leonard_cli/test/drive_dual_e2e_test.dart`, modeled on m4's `launch_dual_e2e_test.dart` + `native_host_e2e_test.dart`:
- **Sync env gate** at `main()`-time: require `LEONARD_NATIVE_SIM_UDID`, `LEONARD_NATIVE_APP` (+ a resolvable native host + Flutter entrypoint); `markTestSkipped` + return when absent.
- **Async reachability probe INSIDE the test body**: `GET <appium>/status` (3s/5s) → `markTestSkipped` when Appium is down. (An HTTP probe in a sync `main()`-time gate would `sleep`-deadlock the isolate and always skip — m4's rule.)
- **Drive shape:** `leonard_drive up` the native dual path → capture `flutter_ws_uri` + `native_endpoint` → `drive-dual tools` (merged manifest has `core` + `native`; AC4/AC12) → `drive-dual observe` (merged JSON has `core` + `extensions.native`; AC12) → `drive-dual invoke --tool native.tap …` (routed; AC12) → `down`. **STOP before SIGN IN** (m5). Drain both stdout+stderr of every spawned process; teardown in `finally` with SIGKILL escalation + temp-dir cleanup.

**Quality gates before handoff:** `melos run analyze`, `melos run test`, `melos run format`. The hardware tier self-skips locally (no sim/Appium), so the default gate stays green for everyone. Land to `feat/leonard-native` only (per the project landing flow: factory lands direct-to-`feat/leonard-native`, gate is analyze-and-test green; push, do not hand-roll a PR).

---

## Key constraints / gotchas the builder must respect

- **`LeonardSession` is the N=1 reference and must NOT change behavior** — only `implements SessionSurface` + a one-line `executeAction` forwarder. Any other diff to `session.dart` is a back-compat regression (AC1).
- **Routing splits on the FIRST dot** — identical to `VmServiceClient.executeAction` (`vm_service_client.dart:171-177`); the tool token may contain further dots (`core.screenshot`). No new name grammar.
- **`DefaultLoopHost.executeAction` body changes** — from `_session.client.executeAction` (`default_loop_host.dart:131`) to `_session.executeAction`. `LeonardSession.client` is `@internal` (`session.dart:145`) and is NOT on `SessionSurface`; actions route through the interface's `executeAction`.
- **Capabilities are de-duped FIRST-SEEN order, NOT sorted** — to match the existing single-host emission (decode order `vm_service_client.dart:141-146`; `leonard_drive.dart:206` emits verbatim). The merged shape must match `drive tools`.
- **Stability merge: framework fields from primary, `extensionsBusy` concatenated.** `StabilityMetadata` (`observation/models.dart:488`): `frameworkBusy` is a `Map<String,dynamic>` (line 532), `extensionsBusy` is a `List<ExtensionBusy>` (line 533, each namespaced). Take `policy`/`terminatedBy`/`durationMs`/`frameworkBusy` from the primary (Flutter) channel verbatim; **concatenate `extensionsBusy`** across hosts. There is NO `frameworkBusy`-union — the native busy signal rides `extensionsBusy`.
- **Contract version: merged/primary, stamped on every record.** `bringUpSession` stamps every `ExtensionManifestRecord` (incl. `native`) with the merged/primary `contractVersion` (`session_bringup.dart:71-74`). A documented m3 limitation — both hosts ship `"2"` today. Per-namespace `contractVersionFor(namespace)` is the deferred clean fix.
- **Namespace collision is a hard error at `start()`, not silent shadowing** (§3.1). The check is over **manifest namespaces** (`handshake.extensions[].namespace`), where the native host reports only `native` (`native_extension.dart:36`) — both hosts also serving the raw `ext.exploration.core.*` VM surface is NOT a manifest `core` entry, so no false positive.
- **Unknown namespace at dispatch is a synchronous hard error** (`MultiHostUnknownNamespace`) thrown before any wire call — the loop must never hang on an unroutable name.
- **The native host's `core` is empty** (pure-Dart `ExplorationHost`, no Flutter semantics); its live signal is `extensions['native']`. The merge takes `core` from the Flutter (primary) host and unions `extensions` — never expect native semantics in `core`.
- **One `StabilityPolicy`, all hosts, join-on-all** (`Future.wait`) — "stable" = all hosts idle. The slowest (native Appium) host gates the turn; that is intended (wait for the whole screen to settle).
- **Ownership is per channel** — a borrowed Flutter channel (DevTools) + an owned native channel dispose independently; `VmServiceClient.dispose` already no-ops on borrowed. `MultiHostSession.end()` disposes each channel.
- **No version-equality gate, no partial-host recovery in m3** — hosts may ship different `contractVersion`s (tolerant merge); a transport loss on any channel terminates the session via the existing `VmServiceConnectionLost` path (single-host parity). Both hardenings are deferred.
- **`leonard_agent` stays Flutter- and io-free** — the `multi_host/` layer uses only `package:vm_service` (via `VmServiceClient`) + pure Dart; all launch/process I/O and the `drive-dual` subcommand live in `leonard_cli`.
- **Context-switching is the model's job** — both fragments every turn, no `switchToAppContext`, no harness host-focus flag. The harness presents and routes; the model perceives and chooses.
