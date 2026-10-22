# Changelog

## 0.4.3

Stable promotion of `0.4.3-dev.2` on Nico's promotion call (2026-10-21). No changes on top; the two prerelease entries below carry the details. Together they make `core.enter_text` type only into a text field that is on screen: it no longer fails on a covered route that was never laid out (PR 208, contributed by @OleksandrKriatovResideo), and no longer writes into a field under a pushed route, on an unselected `IndexedStack` tab, or beneath a non-opaque route.

## 0.4.3-dev.2

- Fix: `core.enter_text` no longer types into a field that is not on screen.
  It picks the `EditableText` whose rect overlaps the target node most, and
  the 0.4.3-dev.1 fix skipped only fields that were never laid out. A route
  that was laid out and then covered keeps its geometry, and so does an
  unselected `IndexedStack` child, so a sign-in field under a pushed profile
  screen, or a search field on another tab, stayed a candidate and could win
  on overlap: the tool wrote into the hidden field and returned `ok: true`.
  The search now walks only on-stage elements (the walk flutter_test's
  `skipOffstage` uses), and a tie goes to the field later in the walk, which
  paints on top, as with a field on a non-opaque route over another.
  (lenny-5bw3t)

## 0.4.3-dev.1

- Fix: `core.enter_text` no longer fails when a covered route holds a text
  field that was never laid out. `resolveEditableText` read the geometry of
  every attached `EditableText`, and the Overlay keeps covered routes
  attached without laying them out, so a page stack built with a text-field
  route already covered (a sign-in screen under a complete-your-profile
  barrier, for one) made the tool return `ok: false` with
  `'hasSize': RenderBox was not laid out` before it typed. Text fields
  without a size are now skipped: they are not on screen to be typed into.

## 0.4.2

Stable promotion of `0.4.2-dev.1` on Nico's promotion call (2026-10-21), after the live check on the macOS sample app and the publish workflow's live macOS gate passed. The prerelease entry below carries the details. One change on top:

- The bundled DevTools panel is rebuilt from current `leonard_devtools`. The copy shipped since 0.4.0 was built on 2026-09-02, before the panel learned the `acp` provider, so apps on published `leonard_flutter` had no way to pick a Copilot or Codex harness (lenny-g7ie4). The panel now offers it; see the `leonard_acp` README for the bridge it needs.

## 0.4.2-dev.1

- Fix: `core.system_back` is a back press, never an app exit (lenny-ssviv). It
  called `SystemNavigator.pop` — the platform's "exit the app" call — so a
  back at the root quit the app and ended the run (seen live on the macOS
  sample app at its Home route). It now dispatches the press the way the
  engine does, through `WidgetsBinding.handlePopRoute` and the app's
  registered observers (the root `Navigator`, a `Router`'s back button
  dispatcher, `PopScope`, an open drawer). When nothing handles it, the tool
  absorbs the press instead of falling back to `SystemNavigator.pop`, so the
  app stays up. The result is still `ok` and now reports
  `{handled, popped}` — `popped: false` means no route left the stack — and
  is carried into the next model turn.

## 0.4.1

Stable promotion of `0.4.1-dev.1`: the same content, published on the stable rung on Nico's promotion call (2026-10-15), after the Android (Pixel 7a), iOS 26.5 simulator and macOS live suites passed. The prerelease entries below carry the full list.

## 0.4.1-dev.1

- Adopt canonical Genesis `Component` and `Element` vocabulary throughout the
  binding and core perception path. Flutter `Widget`, `Element`, and
  `BuildContext` remain explicitly distinct from Genesis tree types.
- Rename `buildCorePerceptionSeed` to `buildCorePerceptionComponent` and use
  `TreeNode.componentType` in source while preserving diagnostics contract 1
  and its literal `seedType` JSON key.
- Require `genesis_perception ^0.4.0` and `leonard_contract ^0.3.0-dev.1`.

## 0.4.0

Promotes `0.4.0-rc.2` to stable. The candidates' full change lists are under
those entries below; the break is restated here because this is the version a
consumer on 0.3.x upgrades to.

- **Breaking: `captureScreenshot` no longer takes a `RendererBinding`.**
  Migration: drop the argument — `captureScreenshot(binding)` becomes
  `captureScreenshot()`.
- Fix: `core.handshake` carries `toolDescriptors` — each registered tool's
  description and raw input schema — beside the bare `tools` names, so a driver
  can reject a malformed call before it reaches the device (lenny#123).
- Add: the `core.remember` and `core.recall` tools — a trim-proof scratchpad
  whose entries survive conversation trimming. Shipped in the 0.4.0-rc.2 archive
  and undocumented there (lenny#116).
- Raise the `leonard_contract` floor to `^0.2.5`, the version that introduces
  `ExtensionRegistry.handshakeManifest`.

## 0.4.0-rc.2

- Fix live `ext.leonard.core.screenshot` capture by calling Flutter's stock
  `WidgetInspectorService.screenshot` implementation in process. This removes
  the app's VM-service self-connection and the package's runtime `vm_service`
  dependency. Screenshot failures now expose six distinct unavailable reasons
  while preserving the four-key success envelope and JSON-RPC error code 1.
- Floors `leonard_contract` to `^0.2.4` (the binding passes `carryForward`, introduced there).

## 0.4.0-rc.1

- **Breaking: `captureScreenshot` no longer takes a `RendererBinding`.** The
  exported top-level function is now `captureScreenshot()`, capturing through the
  stock Flutter inspector screenshot protocol behind one bounded capture path
  instead of protected `RenderView` layer capture. Migration: drop the argument —
  `captureScreenshot(binding)` becomes `captureScreenshot()`. Leonard's response
  and failure envelopes are unchanged, and the extension now registers through
  the catalog seam. `ScreenshotConfig` gains the inspector capture timeout,
  object group, and argument builder.
- Add `core.tap_at`: a strict fractional tap that resolves logical coordinates
  inside an observed semantics node's rect and drives them through the existing
  hit-test path. The strict `core.tap` contract is unchanged.
- Raise the `leonard_contract` floor to `^0.2.2`; the declared `^0.2.0` floor was
  unsatisfiable against this package's own `genesis_perception` range.

## 0.3.1

- Fix: `core.enter_text` now enters text through
  `EditableTextState.userUpdateTextEditingValue` (the same path a physical
  keystroke uses) instead of assigning `controller.value` directly. `onChanged`
  was never fired before, leaving app state that depends on it — button
  enablement, `Form` validation — stale after `enter_text`. Submission
  callbacks are unaffected: `onSubmitted`/`onFieldSubmitted` fire from
  `performAction`, not from an edit, so `enter_text` still does not submit.
  No API changes.

## 0.3.0

- Breaking: test helpers no longer ship from `leonard_flutter`. Add
  `leonard_flutter_test: ^0.1.0` to `dev_dependencies` and import its barrel
  instead. Imports of the deleted
  `package:leonard_flutter/test_support/perception_serializer.dart` must use
  `package:genesis_perception/genesis_perception.dart` directly.

## 0.2.2

- feat: on-demand `ext.leonard.core.get_diagnostics_tree` diagnostics
  extension. Projects the core + registered perception extensions to Genesis
  diagnostics contract 1 only when requested (e.g. while the DevTools
  Diagnostics panel is open) — `get_stable_observation`'s hot path is
  unchanged and still carries no diagnostics tree. A plain `leonard_flutter`
  dependency automatically discovers the bundled Leonard DevTools extension
  with Conversation and Diagnostics modes; no adopter dependency on
  `leonard_devtools` or `genesis_foundation` is required.
- Fix: move the test-only `leonard_agent` dependency to `dev_dependencies`,
  so applications can install `leonard_flutter` alongside packages that use
  `sse_channel ^0.1.1` (including `signalr_netcore`) without a version-solving
  conflict. No public API or runtime behavior changes.

## 0.2.1

- Bump `genesis_perception` to `^0.2.0` (the genesis builder wave). No API
  changes in this package; the perception wire contract is unchanged.

## 0.2.0

- Breaking: VM-service methods now use `ext.leonard.*`. Construct names with
  `kLeonardExtensionPrefix` from `leonard_contract`.
- The binding emits `kLeonardProtocolVersion` in its handshake.

## 0.1.8

- Republish so the pub.dev archive actually carries `LeonardBinding.extensionsReady`
  (a `Future<void>` that completes once the leonard service extensions are
  registered). The getter landed in the repo while the version stayed 0.1.7, so
  the hosted 0.1.7 archive predates it and consumers pinning `^0.1.7` from
  pub.dev could not compile against it (butane_flutter-s2w).

## 0.1.7

- The core semantics fragment now emits `identifier` (from
  `SemanticsData.identifier`, set via `Semantics(identifier:)`) alongside
  `label` and `value` — a stable, locale-independent key for addressing a node.
  Emitted present-only, so apps that set no identifiers are unaffected.

## 0.1.6

- The core semantics fragment now emits a `value` field (from
  `SemanticsData.value`) alongside `label`, so the harness sees a node's current
  value (e.g. a text field's contents) uniformly with the native channel's
  record shape.
- Stability: the settle loop no longer wedges when a framework callback stays
  registered across frames — the persistent-callback baseline is dropped from
  `isAnyBusy`, so a quiet frame is correctly reported as idle.

## 0.1.5

- `core.handshake` now advertises a `capabilities` list alongside the extension
  manifest. `screenshot` (the raw `core.screenshot` VM extension) is reachable
  but is not a namespaced tool, so it never appeared in the manifest — a driver
  listing tools would wrongly conclude "no screenshot". It is now reported as a
  capability, gated on the same debug/profile condition as the extension itself
  (absent in release).

## 0.1.4

- Extension contract extracted to the new `leonard_contract` package
  (Flutter-free): `LeonardExtension`, `LeonardTool`, `PerceptionExtension`,
  `ExtensionRegistry`, and the dispatch helpers now live there and are
  re-exported via `contract.dart`, so consumers are unaffected. Adds a
  `leonard_contract` dependency. The unused frame-callback and error-handler
  hooks were dropped, removing the `SchedulerBinding` / `FlutterErrorDetails`
  coupling from the contract; the binding's error-ring-buffer capture is
  unchanged.

## 0.1.3

- Perception serialization de-duplicated: `serializePerceptionFragment` now
  lives in `genesis_perception` and is re-exported here. Bumps the
  `genesis_perception` floor to `^0.1.2` (the version that introduced it).
- Observation: expose scroll extent (`pos` / `min` / `max`) on scrollable
  nodes, so the agent can see scroll position and bounds instead of guessing.

## 0.1.2

- Fix: a new agent handshake resets the session-terminated latch set by
  `core.done`. Previously, reusing one running app across multiple agent
  drives left the binding permanently terminated after the first drive's
  `core.done`, so every subsequent action returned `session_terminated` and
  the agent appeared stuck (model-agnostic). `core.handshake` now clears the
  latch — a handshake marks the start of a new session.

## 0.1.1

- Fix: ship the compiled DevTools extension bundle in the published package.
  0.1.0 omitted `extension/devtools/build/` because the repo-root `build/`
  `.gitignore` rule excluded it (`pub publish` honors `.gitignore`), so the
  "Leonard" DevTools tab was missing for consumers. The bundle is now
  un-ignored and shipped.

## 0.1.0

- Host `WidgetsBinding` (`LeonardBinding`) with a single-path perception
  observation pipeline (`PerceptionOwner`-backed serialization).
- `LeonardExtension` authoring contract; core fragment is perception-native.
- Ships the DevTools extension (the "Leonard" tab) via `extension/devtools/`.
- VM-service surface `ext.leonard.*` (protocol-stable).
