---
name: test-with-leonard
description: >
  Author tests and improve coverage for Dart and Flutter apps with Leonard. Use
  when asked to "write a test for my Flutter app", "add coverage with lenny",
  or "test this screen end to end". This skill owns test authoring and choosing
  the cheapest level that can prove the behaviour. Use the
  `drive-with-leonard` skill when asked to drive a running app toward a goal.
---

## Routing

Read the table top-down and take the first level that can prove the behaviour. Level 0 is the default when it is sufficient; reaching for a device when a widget test or golden can prove the behaviour is a routing error.

| Level | Single deciding question | Load |
| --- | --- | --- |
| none (level 0) | Can a widget test or golden prove it? | Read `references/plain-dart-flutter.md` when a widget test or golden can prove it. |
| widget/unit | Does the test need no device because it covers an extension or observation? | Read `references/widget.md` when no device is required and the test covers an extension or observation. |
| scripted device | Does the test need a real Flutter app on a simulator or emulator? | Read `references/scripted-device.md` when the test needs a real Flutter app on a simulator or emulator. |
| hardware | Does the behaviour exist only on a physical device? | Read `references/hardware.md` when the behaviour exists only on a physical device. |
| oracle-graded | Must the test judge whether the agent reached the goal? | Read `references/oracle.md` when the test must grade whether the agent reached the goal. |

- Read `references/triage.md` when a run failed and the cause is unclear.
- Read `references/mutation.md` when the ask is coverage quality rather than a new test.

## Gotchas

* `SessionOutcome.done` is the MODEL calling `core.done`. It is a self-report, not an oracle. A test whose only assertion is `outcome == done` asserts that the model believed itself.
* `ext.gauntlet.oracle` is registered DELIBERATELY outside `ext.flutter.exploration.*` and contributes no observation fragment, so the driving agent cannot read the answer out of its own bundle. That separation is the whole reason level 4 grades anything. An oracle that leaks into the observation is not an oracle.
* `LeonardBinding` is a custom WidgetsBinding and THROWS on IntegrationTestWidgetsFlutterBinding (packages/leonard_flutter/lib/src/binding/leonard_binding.dart:185). You cannot drive an app under `package:integration_test`. PRD v0.5 §162.
* lenny's `integration_test/` directories are a plain directory name run by `dart test`. NO pubspec in the repo depends on `package:integration_test`. The collision of names is the single most likely thing for a consumer to get wrong.
* Every live tier calls `markTestSkipped` and exits 0 without its env vars. A lenny e2e suite can therefore NEVER be a station validation_plan — it passes vacuously. Say this where the agent will read it before wiring a gate.
* `melos test` (the default gate) EXCLUDES the integration suites by design. They run only under `melos test:integration`.
* The automated suites target simulator/emulator; hardware is the manual runbook. The intuition is backwards and consumers will assume the opposite.
