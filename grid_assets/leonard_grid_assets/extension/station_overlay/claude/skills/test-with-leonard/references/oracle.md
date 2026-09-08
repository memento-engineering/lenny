# Grade a gauntlet run independently

Level 4 adds a separate grader after a live drive when the question is whether the agent reached the goal. `GauntletLiveHarness` is the gauntlet entrypoint (`packages/leonard_flutter/example/sample_app/test/gauntlet/gauntlet_live_harness.dart:100-164`). Use it only after the cheaper proving levels in `grid_assets/leonard_grid_assets/extension/station_overlay/claude/skills/test-with-leonard/SKILL.md:13-21` cannot answer that question.

## Separate the driver from the grader

`GauntletDriver` returns only the driving agent's `reported` map (`packages/leonard_flutter/example/sample_app/test/gauntlet/gauntlet_live_harness.dart:7-11`). The harness awaits that result first (`packages/leonard_flutter/example/sample_app/test/gauntlet/gauntlet_live_harness.dart:130-134`), then asks the separately injected `GauntletOracleReader` to read the VM-service back-channel (`packages/leonard_flutter/example/sample_app/test/gauntlet/gauntlet_live_harness.dart:70-97`, `packages/leonard_flutter/example/sample_app/test/gauntlet/gauntlet_live_harness.dart:100-107`). The verdict therefore comes from private app state after the driver returns, not from the driver's claim.

`ScenarioOracleState` is declared at `packages/leonard_flutter/example/sample_app/lib/gauntlet/scenario_oracle.dart:15`. Its hidden `expected` values, `goalReached` marker, and serialized `scenario_id`, `expected`, `goal_reached`, and tap fields are defined at `packages/leonard_flutter/example/sample_app/lib/gauntlet/scenario_oracle.dart:23-55`. The sample app registers the debug channel at `packages/leonard_flutter/example/sample_app/lib/main.dart:18-20`.

`ext.gauntlet.oracle` is registered at `packages/leonard_flutter/example/sample_app/lib/gauntlet/scenario_oracle.dart:79`, deliberately outside `ext.flutter.exploration.*`, and contributes no observation fragment. The driving agent therefore cannot read the grader's hidden answer from its own observation bundle. That privacy contract is documented at `packages/leonard_flutter/example/sample_app/lib/gauntlet/scenario_oracle.dart:6-13`, and the assert-wrapped, debug-only extension is implemented at `packages/leonard_flutter/example/sample_app/lib/gauntlet/scenario_oracle.dart:65-103`. An observation leak invalidates the oracle.

## Claim 1 — Interaction success

**Proves:** `GauntletLiveHarness` accepts an interaction scenario only when the private `goal_reached` value is true after the driver returns (`packages/leonard_flutter/example/sample_app/test/gauntlet/gauntlet_live_harness.dart:120-148`, `packages/leonard_flutter/example/sample_app/test/gauntlet/gauntlet_live_harness_test.dart:67-97`).
**Command:** `cd packages/leonard_flutter/example/sample_app && flutter test test/gauntlet/gauntlet_live_harness_test.dart --plain-name 'settle/decorative-motion passes only when goal_reached is true'`
**Falsifier:** Return `goal_reached: false` from the private reader after the driver finishes.
**Failure signature:** `Bad state: settle/decorative-motion: goal_reached is false`

## Claim 2 — Reported-answer correctness

**Proves:** Answer scenarios compare every hidden `expected` entry with the driver's `reported` value and require the goal to name every expected key (`packages/leonard_flutter/example/sample_app/test/gauntlet/gauntlet_live_harness.dart:151-163`, `packages/leonard_flutter/example/sample_app/test/gauntlet/gauntlet_live_harness_test.dart:99-169`).
**Command:** `cd packages/leonard_flutter/example/sample_app && flutter test test/gauntlet/gauntlet_live_harness_test.dart --plain-name 'answer verdict rejects a mismatched reported value'`
**Falsifier:** Report `count: 9` while the private expected value is `count: 8`.
**Failure signature:** `Bad state: vision/count-spatial: answer mismatch for count`

## Completion claims and observed evidence

`SessionOutcome.done` records the model's voluntary `core.done(reason)`, not independent success (`packages/leonard_agent/lib/src/loop_driver/loop_driver.dart:450`, `packages/leonard_agent/lib/src/loop_driver/loop_driver.dart:482-489`). Its final summary is the model-supplied reason (`packages/leonard_agent/lib/src/loop_driver/types.dart:66-68`), so it remains a self-report: the model saying it finished is not evidence.

Before completion is admitted, an observation must prove the completion claim. `docs/decisions/2026-09-01-a4-core-done-is-gated-by-a-scenario-declared-reason-form.md:21-33` gates the reason form; `docs/decisions/2026-09-01-a5-core-done-is-additionally-gated-by-an-observed-evidence-p.md:21-37` gates it against observed evidence. Those checks strengthen a self-report but do not replace the post-drive private oracle.

## Cost and level boundary

Level 4 costs per-scenario app instrumentation through `ScenarioHost`, maintained hidden expected values or success markers, a debug VM-service side-channel, a running app and VM service, a model drive, and separate grader maintenance. The instrumentation lifecycle is at `packages/leonard_flutter/example/sample_app/lib/gauntlet/scenario_oracle.dart:105-167`.

That cost is not worth paying when a cheaper unit, widget, golden, extension-observation, scripted-device, or hardware assertion can directly prove the behavior. Follow the cheapest level rule at `grid_assets/leonard_grid_assets/extension/station_overlay/claude/skills/test-with-leonard/SKILL.md:13-21`.

The harness grades only encoded `goalReached` or `expected` fields. It cannot judge an uninstrumented or subjective goal, and it cannot correct stale or wrong ground truth. It fails closed on inactive, malformed, mismatched, empty, or wrong-scenario oracle data (`packages/leonard_flutter/example/sample_app/test/gauntlet/gauntlet_live_harness.dart:135-163`).
