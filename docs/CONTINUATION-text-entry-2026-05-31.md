# Continuation — Text Entry hardening (lenny exploration agent)

**Date paused:** 2026-05-31 · **Status:** PAUSED at a clean reset point.
**Why paused:** the factory (factoryskills/`fs`) is being **rebuilt and will operate
differently**. Do not invest in the old factory mechanics or the bd-claim workaround below —
they are expected to change. The *technical* work (diagnosis + specs) is durable and is what
this doc preserves.

> Recall first: `bd prime` and read the memory `end-to-end-milestone-2026-05-31-the`.
> This doc is the long form of that memory.

---

## 1. Mission

Get the lenny exploration agent to drive a **live Flutter app to end-to-end goal completion**,
one integration at a time, via the `/harden` loop (run live agent → inspect trajectory →
root-cause → file bead → factory → re-verify). This session's target: **text entry**
(`core.enter_text`). Tap-only goals already complete on a real iPad (the 2026-05-31 milestone:
tap Sign In → login→home → `core.done`). Text entry and go_router navigation do **not** yet.

Architecture in one line: the agent perceives **only** via Flutter's **semantics
(accessibility) tree** and acts via `SemanticsAction`s (with a synthesized-pointer fallback).
That choice is app-agnostic but lossy/frame-coupled — text entry is where it's weakest.

---

## 2. What was VERIFIED live this session (the durable gold)

Diagnosed on the **physical iPad mini (DPR 2.0)** with a temporary instrumented build of
`enter_text` + a VM-service probe. **All instrumentation was reverted; the probe was deleted.**

The previous lenny-c94 hypothesis ("`enter_text` needs to focus before `setText`") is **WRONG** —
`enter_text` already focuses. The real failure has **two compounding causes**:

1. **Node split.** The sample app's login fields are
   `Semantics(label:'email', textField:true, child: TextField(...))`
   (`packages/exploration_flutter/example/sample_app/lib/screens/login_screen.dart:66`).
   The **agent-facing** semantics node (the wrapper, e.g. stable id 4, `label='email'`)
   advertises **NO actions at all** (no `tap`, no `focus`, no `set_text`). The node that
   actually accepts `set_text` is a **different** node — the editable (`label="Email"`), which
   only advertises `set_text` **while focused** and **only on a later frame**.

2. **DPR coordinate bug** (→ now its own bead, **lenny-22f**). Because the wrapper advertises no
   action, `enter_text` falls to its `hitTestTap(globalRectOf(node))` coordinate path.
   `globalRectOf` (`core_tools/dispatch.dart:35`) walks the full semantics parent chain, which
   includes the semantics-root **devicePixelRatio** transform, so it returns **physical** pixels.
   The framework interprets synthesized `PointerEvent.position` as **logical** pixels (the
   engine's converter divides by DPR before events reach `GestureBinding`). On the DPR-2 iPad the
   tap lands at **2× the target and misses** → the field never focuses → `set_text` never appears.

   Hard numbers from the probe: email field observation rect `[403,322,731,378]`;
   `globalRectOf` returned `(805,644,1461,756)` = **exactly 2×**. A **DPR-corrected** tap
   (`globalRectOf/dpr`) **did** focus the editable (keyboard popped, layout shifted up) and a
   separate node then advertised `set_text` — proving both the node-split and that corrected
   focus works.

Buttons are unaffected because they advertise `SemanticsAction.tap` and use the **coordinate-free**
`performAction` path — which is why the milestone's Sign-In tap worked but text fields don't.

Note: `semantics_capture._actions` serializes `SemanticsAction.setText` → **`'set_text'`** and does
**not** serialize `SemanticsAction.focus` at all, so the model never even sees a focus affordance.

---

## 3. The architecture DECISION (made by the user this session)

**Widget-tree path for text entry.** Instead of fighting the semantics
`focus → frame → setText` dance, `core.enter_text` should:

1. `extension.lookupNode(node_id)` → target `SemanticsNode` (+ its global rect).
2. Resolve that node → the corresponding **`EditableText` `State`** by walking the in-process
   element tree from `WidgetsBinding.instance.rootElement`, collecting `EditableText` elements,
   and matching by **geometry** (largest rect intersection with the target node's global rect).
3. Set the controller **directly**:
   `controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length))`.
   (Spec chose `controller.value` over `userUpdateTextEditingValue` to avoid focus side-effects.)

This bypasses `set_text`/focus/frame entirely and does **NOT** depend on the DPR fix (no pointer
synthesis). The new capability (semantics-node → `Element` resolution) does not exist yet —
`inspect_widget` punted on it (see **lenny-37d**, which wants the same thing; share the pattern).
Prior-art note from the committee: `observation/core_fragment.dart` already walks the element tree
with `rootElement` + `visitChildElements` + `StatefulElement` — reuse that pattern.

The DPR fix (lenny-22f) is still worth landing **independently** — it silently breaks
tap/scroll/gesture coordinate fallbacks on **every** real device, not just text entry.

---

## 4. The three beads (all specs written; NO code built or merged)

| Bead | P | Status | What it is |
|------|---|--------|-----------|
| **lenny-c94** | P2 | ready (blocked by whn) | `enter_text` widget-tree path. Spec **committee-approved** (concreteness/decision-density/scope/coherence/decisions A; prior-art B). |
| **lenny-whn** | P1 | ready | Semantics on real device. Mechanism **PROVEN** live. **Re-specced** this session. |
| **lenny-22f** | P1 | open | DPR coordinate bug (physical→logical for pointer fallbacks). Independent of c94. |

**lenny-c94 spec** (in its `design` field): new file
`packages/exploration_flutter/lib/src/core_tools/editable_resolver.dart` with
`resolveEditableText(Rect targetGlobalRect)`; rewrite of
`core_tools/tools/enter_text_tool.dart` `call()`; acceptance test that drives the **tool**
(not `tester.enterText`) against a `Semantics(textField:true, child: TextField())` tree, targets
the **wrapper** node, asserts the controller text changed, and **fails against current code**
(anti-theatre). Manual iPad dogfood step is in the Validation Plan, gated on lenny-whn.

**lenny-whn spec** (re-specced this session — the prior build was rejected for a coverage-theatre
test): PRESERVE the proven `captureAsync()` mechanism (await `SchedulerBinding.instance.endOfFrame`
when `rootSemanticsNode` is null on first call); REPLACE the theatre integration test with a
**regular widget test** at `packages/exploration_flutter/test/semantics/semantics_capture_racing_test.dart`
that reaches the racing state and asserts sync `capture()` returns `[]` while `captureAsync()`
returns the populated tree (goes RED if the fix is reverted); ADD a **bounded** `endOfFrame`
timeout (250 ms) so an occluded/non-pumping window degrades to empty-fast instead of hanging; ADD
the `scroll_tools.dart:188` migration `snapshotSemantics()` → `await snapshotSemanticsAsync()`.
Dependency: **lenny-c94 depends on lenny-whn** (the agent must *see* the field to type into it).

**lenny-22f spec** (acceptance criteria): convert the node global rect from physical → logical
(÷ view `devicePixelRatio`) at a single chokepoint in `core_tools/dispatch.dart` so
`hitTestTap`/`hitTestLongPress`/`hitTestDrag`/`hitTestPinch` all benefit; a binding test with
`devicePixelRatio=2` asserting the synthesized `PointerDownEvent.position` equals the node's
**logical** center (not 2×). `globalRectOf` is used **only** for pointer synthesis (the
observation rect is computed separately in `semantics_capture._walk`), so converting it is safe.

---

## 5. Critical path to a live text-entry win

```
lenny-whn (semantics on device)  ──►  lenny-c94 (widget-tree enter_text)  ──►  live verify on iPad
            land first                  build once whn is on main              (agent types into login form)
lenny-22f (DPR)  ──►  independent; land any time (fixes tap/scroll/gesture on all real devices)
```

- **lenny-whn must land first** — it's the foundation (agent can't type into a field it can't see)
  and c94 has a hard dependency on it.
- The stale `fs/lenny-whn/...` worktree + local branch were **removed** (they predated lenny-4jn/
  lenny-23m and would have reverted them). Any whn rebuild must start **fresh off `main`**. The
  proven `captureAsync` code is recoverable from the spec and from `origin/fs/lenny-whn/...`
  (still on the remote).

---

## 6. The bd / factory blocker (do NOT patch — factory is being rebuilt)

`fs forge` failed to claim the routed `ready` bead. Root cause, fully diagnosed:

- `bd update --claim` is a conditional SQL update hardcoded to `WHERE status = 'open'`
  (`internal/storage/issueops/claim.go:53,59`). It exists in **both** installed bd versions
  (`1.0.4` and the `HEAD-8de88e1` linked **May 30 08:47**, ≈ this session's "tool problems").
  The factory's custom `ready` status is therefore **not claimable** → `fs forge` aborts.
- Compounding: **every** custom status in bd's `custom_statuses` table has
  `category = 'unspecified'` (lost in the embedded→server migration — same class as the saved
  `factory-lifecycle-status-ready-was-missing-from-bd` memory). Valid categories are
  `active` / `wip` / `done` / `frozen`; `unspecified` also excludes these statuses from `bd ready`.
  Set via e.g. `bd config set status.custom "ready:active,in_spec:active,spec_review:wip,code_review:wip,recorded:done"`.

This is left untouched on purpose — the new factory will change how claim/lifecycle works.

---

## 7. Reset point / repo state (clean)

- `main` @ **`2d673a4`** — **no code changes anywhere**. Every fix this session lives only as a
  spec in a bead. Nothing to unwind.
- No `whn/c94/22f` worktrees; no leftover flutter/dart/probe processes; instrumentation reverted;
  probe (`packages/exploration_agent/tool/probe_enter_text.dart`) deleted (the other `tool/`
  scripts there are pre-existing — leave them).
- Uncommitted, pre-existing, **non-code** (do not "clean up" blindly):
  `.claude/skills/harden/` (the harden skill — keep), `.beads/interactions.jsonl`, `.gitignore`,
  `.factoryskills/sessions.jsonl`, `packages/exploration_flutter/example/sample_app/macos/Podfile`.
- `origin/fs/lenny-whn/core-semantics-capture-returns-0-nodes-o` still exists on the remote
  (local copy removed).

---

## 8. How to resume

1. **`bd prime`**, read memory `end-to-end-milestone-2026-05-31-the`, then this doc.
2. **Re-validate the three beads survived the factory rebuild.** Confirm `lenny-whn` (P1, ready),
   `lenny-c94` (P2, ready, depends-on whn), `lenny-22f` (P1, open) still hold their specs in the
   `design` field. If the new factory re-imports/normalizes beads, the specs in §4 are the source
   of truth to restore.
3. **Drive the critical path** (§5) through the *new* factory: land lenny-whn → build lenny-c94 →
   live-verify. lenny-22f in parallel.
4. **Device setup for live verify** (the `/harden` loop):
   - Wire the iPad mini (`00008110-001651523CE3801E`). It must show in `flutter devices`
     **without** `(wireless)` — if it shows wireless while plugged in, uncheck "Connect via
     network" in Xcode → Devices (wireless VM-service discovery hangs ~75 s).
   - `cd packages/exploration_flutter/example/sample_app && flutter run -d <id> --no-devtools`
     (background). Grab the `Dart VM Service … http://127.0.0.1:PORT/TOKEN/` line → convert to
     `ws://127.0.0.1:PORT/TOKEN/ws`. The app **stays attached**; only the CLI recompiles.
   - **Build the app from a worktree that carries whn's semantics + c94's enter_text fix** (or
     land whn first so `main` has semantics). Run the **agent CLI from `main`**.
   - `source ~/.lenny-dogfood.env` (provides `ANTHROPIC_API_KEY` scoped to pay-as-you-go API —
     keep it OUT of `~/.zshenv`).
   - The app launches at **login**; if it's on **home** (a prior run logged in), the agent/probe
     can tap the **"Log Out"** button (it advertises `[tap]`) to return to login.
5. Use the **`/harden text entry`** skill to orchestrate.

### Useful probe recipe (re-derive if needed)
A standalone Dart script using `package:vm_service` (deps live in `exploration_agent`) can drive
the live app deterministically: connect to the ws URI, pick the isolate exposing
`ext.flutter.exploration.core.get_semantics`, then call extensions:
- `core.get_semantics` → `{semantics:[{id,role,rect,label?,state?,actions?}], count}`
- `core.tap` / `core.enter_text` with args as VM params (`node_id:'4'`, `text:'"x"'` — values are
  JSON-decoded by `decodeServiceExtensionParams`).
This is how the node-split + DPR facts in §2 were captured.

---

## 9. Discipline / gotchas (hard-won)

- **Verify before concluding.** This whole diagnosis overturned the bead's stated hypothesis by
  capturing real data on the device. Check the mundane cause first (occluded window, disabled
  extension, wrong coordinate space) before the dramatic one.
- **Revert all instrumentation; delete scratch probes** before filing/speccing. (Done.)
- **Non-theatre tests:** a test must go RED against the old code. The committee rejected a
  semantics test that pre-pumped the tree so `capture()` == `captureAsync()`. The new c94 and whn
  specs both bake in the "fails on old code" proof.
- **`ANTHROPIC_API_KEY`** stays in `~/.lenny-dogfood.env` (pay-as-you-go API billing), never
  `~/.zshenv`. When editing shell profiles, touch only the authorized line.
- **No `bd` comments with `--actor human`** (impersonation).
- **Don't commit/push without explicit authority.** Conservative default.

---

## 10. Key source files (anchors)

| Concern | File |
|---|---|
| `enter_text` tool (rewrite target, c94) | `packages/exploration_flutter/lib/src/core_tools/tools/enter_text_tool.dart` |
| `globalRectOf` / `hitTest*` (DPR bug, 22f) | `packages/exploration_flutter/lib/src/core_tools/dispatch.dart` |
| `captureAsync`/`capture`, `_walk`, `_actions` (whn) | `packages/exploration_flutter/lib/src/semantics/semantics_capture.dart` |
| Extension registration + arg decode | `packages/exploration_flutter/lib/src/binding/exploration_binding.dart` |
| `lookupNode`, `snapshotSemanticsAsync`, `decodeServiceExtensionParams` | `packages/exploration_flutter/lib/src/core_tools/core_plugin.dart` |
| `snapshotSemantics()` call to migrate (whn) | `packages/exploration_flutter/lib/src/core_tools/tools/scroll_tools.dart:188` |
| element-tree access punt (related: lenny-37d) | `packages/exploration_flutter/lib/src/core_tools/tools/inspect_widget_tool.dart` |
| element-tree walk precedent to reuse | `packages/exploration_flutter/lib/src/observation/core_fragment.dart` |
| sample app login fields (wrapper/editable split) | `packages/exploration_flutter/example/sample_app/lib/screens/login_screen.dart` |
| the harden loop | `.claude/skills/harden/` |

## 11. Other open blockers (not this session's target)
- **lenny-18q** (P2): `router.navigate` broken for go_router (uses `pushNamed`/`onGenerateRoute`).
- **lenny-37d** (P2): `inspect_widget` element-tree via WidgetInspectorService — shares c94's
  node→Element need.
- **lenny-jfh / lenny-jox / lenny-mab / lenny-wfj** — see `bd list`.
