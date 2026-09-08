# Prove it before launching an app

Level 0 is the default when static checks or hermetic Dart and Flutter tests can distinguish the correct program from a named breaking change. Keep the proof here when it needs no running app. Run every command from the repository root.

## Static policy

**Proves:** The root analyzer accepts the package graph under `strict-casts`, `strict-inference`, `strict-raw-types`, `prefer_single_quotes`, `sort_pub_dependencies`, `unawaited_futures`, and `avoid_print` (`analysis_options.yaml:1-18`). CI runs this gate at `.github/workflows/ci.yaml:18-24`.

**Command:** `dart analyze`

**Falsifier:** At `packages/leonard_contract/lib/src/strike_counter.dart:9`, replace the initializer with `int _consecutive = 'zero';`.

**Failure signature:** An `invalid_assignment` diagnostic and a non-zero exit.

**Measured receipt:** On the 2026-09-08 base, the command exited zero with `2 issues found`; both were info-level `depend_on_referenced_packages` diagnostics. Do not report info lints as fatal when the command succeeds.

## Pure-Dart behavior

**Proves:** The strike counter trips at its limit and a success resets consecutive failures. The behavior and its assertions are at `packages/leonard_contract/lib/src/strike_counter.dart:11-18` and `packages/leonard_contract/test/strike_counter_test.dart:5-31`.

**Command:** `cd packages/leonard_contract && dart test test/strike_counter_test.dart`

**Falsifier:** Replace the reset with `void recordSuccess() => _consecutive++;`.

**Failure signature:** The reset case reports `Expected: false` and `Actual: <true>`.

**Measured receipt:** On the 2026-09-08 base, the command reported `+2: All tests passed!`.

## Flutter-package unit behavior

**Proves:** `RouterPerception` reads a `RouteSnapshot` through `RouteSnapshotAnchor` and serializes the exact populated and defensive-empty router maps without constructing a widget or installing a binding (`packages/leonard_router/lib/src/router_perception.dart:21-33`, `packages/leonard_router/lib/src/router_perception.dart:42-49`, and `packages/leonard_router/test/unit/observation/router_perception_test.dart:9-52`).

**Command:** `cd packages/leonard_router && flutter test test/unit/observation/router_perception_test.dart`

**Falsifier:** Replace `RouteSnapshot? read() => _extension.readSnapshot();` with `RouteSnapshot? read() => null;`.

**Failure signature:** `snapshot becomes the exact router perception shape` reports that the expected populated route map was replaced by null `current_route_name` and `arguments` plus an empty `stack`.

**Measured receipt:** On the 2026-09-08 base, the command reported `+2: All tests passed!`.

## Flutter widget and golden behavior

**Proves:** The router perception emits the expected route fields and stays byte-equivalent to its committed golden. The producer and tests are at `packages/leonard_router/lib/src/router_perception.dart:21-33` and `packages/leonard_router/test/widget/extension/router_perception_equivalence_test.dart:82-171`.

**Command:** `cd packages/leonard_router && flutter test test/widget/extension/router_perception_equivalence_test.dart`

**Falsifier:** Replace the route-name field with `Field('currentRouteName', snap?.currentRouteName)`.

**Failure signature:** The happy-path test reports a missing `current_route_name` expectation, and the golden case reports a golden JSON mismatch.

**Measured receipt:** On the 2026-09-08 base, the command reported `+5: All tests passed!`.

## Runtime dependency boundary

**Proves:** The agent stays Flutter-free, the agent and DevTools libraries stay `dart:io`-free, and the VM-service I/O import stays confined to its seam. The guard is at `tool/check_no_dart_io.sh:18-70`, CI invokes it at `.github/workflows/ci.yaml:22-24`, and a guarded import location is `packages/leonard_agent/lib/src/vm_service_client.dart:10`.

**Command:** `./tool/check_no_dart_io.sh`

**Falsifier:** Add `import 'dart:io';` at `packages/leonard_agent/lib/src/vm_service_client.dart:10`.

**Failure signature:** `ERROR: packages/leonard_agent/lib must not import dart:io` and a non-zero exit.

**Measured receipt:** On the 2026-09-08 base, the command reported `OK: leonard_agent is Flutter-free; leonard_agent + leonard_devtools libs are dart:io-free; vm_service_io is confined to packages/leonard_agent/lib/src/vm_service_client_io.dart`.

## Live boundary

Unit, widget, and golden checks cannot observe real rendering on a device, real gestures, real platform channels, or anything requiring a live VM service. Escalate when the behavior depends on any of those observables.

Testing Leonard packages or types hermetically stays at level 0; level 0 does not launch or drive a running app with Leonard. Use `package:integration_test` as the level-0 exception when Flutter owns the integration run and Leonard is absent. The moment Leonard drives the running app, leave level 0 and follow the router; its binding constraint is already recorded at `grid_assets/leonard_grid_assets/extension/station_overlay/claude/skills/test-with-leonard/SKILL.md:30`.
