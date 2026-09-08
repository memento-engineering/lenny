# Prove behavior on physical hardware

Level 3 is a manual runbook; no automated lane runs level 3. The automated device suites use a simulator or emulator, while a human follows this reference on attached hardware. The router makes that distinction and sends independent judgment onward (`grid_assets/leonard_grid_assets/extension/station_overlay/claude/skills/test-with-leonard/SKILL.md:19-21`, `grid_assets/leonard_grid_assets/extension/station_overlay/claude/skills/test-with-leonard/SKILL.md:32-34`).

## Claim 1 — Wired iOS/iPad dogfood

**Proves:** A goal can be driven and its device-visible result inspected in the real sample app on a wired iOS device, including an iPad, without losing the attached VM-service session.

**Command:** Execute the authoritative command blocks in `docs/RUNBOOK-e2e-dogfood.md` in place. Use its prerequisites (`docs/RUNBOOK-e2e-dogfood.md:17-41`), device attach check (`docs/RUNBOOK-e2e-dogfood.md:45-50`), attached app session (`docs/RUNBOOK-e2e-dogfood.md:52-67`), agent invocation (`docs/RUNBOOK-e2e-dogfood.md:69-86`), trajectory inspection (`docs/RUNBOOK-e2e-dogfood.md:88-102`), pass/fail inspection (`docs/RUNBOOK-e2e-dogfood.md:103-126`), and reset, teardown, and `iproxy` cleanup (`docs/RUNBOOK-e2e-dogfood.md:128-145`). Those sections are the sole source of truth for device identifiers, environment setup, launch, inspection, and cleanup commands.

**Falsifier:** Detach the target before the device attach check.

**Failure signature:** The target is absent from the device listing or is marked `(wireless)`, and the attached launch produces no VM-service URI.

## Claim 2 — Android permission-dialog proof

**Proves:** The proof tool captures a real Android runtime permission dialog and verifies the three supported actions against a fresh attached-device capture. A permission dialog in the UiAutomator2 `/source` hierarchy has a recognized permission-controller `resource-id` ending in `:id/grant_dialog`, with `permission_allow_button` and `permission_deny_button` children (`packages/leonard_native/tool/android_permission_dialog_proof.dart:219-240`, `packages/leonard_native/test/fixtures/android_permission_dialog_source.xml:20-35`). The localized visible strings are capture evidence rather than detection keys.

**Command:** From the repository root, run the tool's accepted capture and verify modes (`packages/leonard_native/tool/android_permission_dialog_proof.dart:705-732`):

```bash
cd packages/leonard_native && dart run tool/android_permission_dialog_proof.dart capture
cd packages/leonard_native && dart run tool/android_permission_dialog_proof.dart verify
```

The action receipt proves dismissal is refused with the dialog still visible, allow closes and grants, and deny closes and does not grant (`packages/leonard_native/tool/android_permission_dialog_proof.dart:307-327`, `packages/leonard_native/tool/android_permission_dialog_proof.dart:594-613`).

**Falsifier:** Replace the captured `grant_dialog` resource id with an unrecognized id.

**Failure signature:** Depending on where the altered capture is observed, the tool reports `grant dialog absent after startup wait` (`packages/leonard_native/tool/android_permission_dialog_proof.dart:232-240`), `captured /source has no permission dialog` (`packages/leonard_native/tool/android_permission_dialog_proof.dart:555-564`), or `live permission action proof failed` (`packages/leonard_native/tool/android_permission_dialog_proof.dart:307-327`).

## Current tool limits

The tool hardcodes `const String serial = 'RF8RB21P6LN';` (`packages/leonard_native/tool/android_permission_dialog_proof.dart:10`), uses it in reset argv (`packages/leonard_native/tool/android_permission_dialog_proof.dart:19-20`), and supplies it to every ADB call (`packages/leonard_native/tool/android_permission_dialog_proof.dart:156-158`). There is no `--serial` argument because `main` accepts only `capture|verify` (`packages/leonard_native/tool/android_permission_dialog_proof.dart:713-727`). Before use, supply your own attached device with a local, uncommitted edit of the serial constant.

The unmodified tool also requires open bead `lenny-91vu` before device IO (`packages/leonard_native/tool/android_permission_dialog_proof.dart:135-153`). That bead is closed, so the current tool fails before device IO with `HARDWARE_PROOF FAIL: Bad state: RF8RB21P6LN unavailable: lenny-91vu must be open`. This is a known tool limitation, not a successful hardware receipt; leave the tool unchanged while following this reference.

## Level boundary

A `markTestSkipped` result or a green simulator or emulator lane is not level-3 evidence. A human device pass over this finished reference is follow-up evidence. Level 3 can exercise and inspect hardware behavior, but it cannot provide an independent verdict that the driving agent reached its goal. Escalate that judgment to level 4 and `references/oracle.md`.
