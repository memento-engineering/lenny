# Cold trace: write a test for RouterPerception in lenny

## Prompt

`write a test for RouterPerception in lenny`

## Route, question by question

1. Read `grid_assets/leonard_grid_assets/extension/station_overlay/claude/skills/test-with-leonard/SKILL.md` from the prompt without inspecting the target package first.
2. The original first deciding question was `Can a widget test or golden prove it?`
3. A hermetic test can prove the synchronous snapshot-to-perception shape without a running app, widget tree, device, VM service, or independent oracle. A widget test could also exercise the shape, but that would be an overpowered proof compared with a direct unit test.
4. Selected level 0 and read only `references/plain-dart-flutter.md`, following the entrypoint's instruction to use the cheapest level that can prove the behaviour.
5. No later routing question or other reference was read. The authored proof is the cheaper unit test, not the possible widget test.

## Findings and corrections

| Finding | Source | Kind | What happened cold | Correction |
| --- | --- | --- | --- | --- |
| F1 — level-0 deciding question omitted hermetic unit tests | `grid_assets/leonard_grid_assets/extension/station_overlay/claude/skills/test-with-leonard/SKILL.md` | Unanswered guidance | The first row named widget and golden tests but not the cheaper hermetic unit proof that fits this task. | The first row now asks whether a static check or hermetic Dart unit, widget, or golden test can prove the behaviour and loads `references/plain-dart-flutter.md` on that basis. |
| F2 — level-0 reference omitted a non-widget Flutter-package example and pointed this target only at its existing widget/golden coverage | `grid_assets/leonard_grid_assets/extension/station_overlay/claude/skills/test-with-leonard/references/plain-dart-flutter.md` | Wrong escalation | The reference supplied no direct unit pattern for a Flutter package and sent RouterPerception work to its existing widget/golden command. | A Flutter-package unit section now records the direct test, command, production and test citations, falsifier, failure signature, and measured receipt. |
| F3 — live boundary conflated testing Leonard code with live Leonard driving | `grid_assets/leonard_grid_assets/extension/station_overlay/claude/skills/test-with-leonard/references/plain-dart-flutter.md` | Wrong escalation | The statement that level 0 does not use lenny and that any lenny participation leaves level 0 incorrectly escalated hermetic tests of Leonard packages. | The boundary now keeps hermetic Leonard package/type tests at level 0 and escalates only when Leonard drives a running app. |

## Execution receipt

Commands ran in this order:

1. `cd packages/leonard_router && flutter test test/unit/observation/router_perception_test.dart` exited 0 with `+2: All tests passed!`.
2. `cd grid_assets/leonard_grid_assets && dart test test/test_with_leonard_skill_test.dart --name 'the router takes the cheapest proving level and names every load|level 0 pins five hermetic gates to falsifiers and receipts|level 0 keeps hermetic Leonard code below the live boundary'` exited 0 with `+3: All tests passed!`.
3. The selected frontmatter, router, and stub asset tests exited 0 with `+3: All tests passed!`; the four paired-description and stub/reference comparisons against `origin/main` also exited 0.
4. The full `grid_assets/leonard_grid_assets` gate (`dart pub get`, `dart analyze`, format check, and `dart test`) exited 0: analysis reported no issues, formatting changed no files, and `+56: All tests passed!`.
5. The full `packages/leonard_router` gate (`flutter pub get`, `dart analyze`, format check, and `flutter test`) exited 0: analysis reported no issues, formatting changed no files, and `+23: All tests passed!`.
6. The full `packages/leonard_cli` gate (`dart pub get`, `dart analyze`, format check, and `dart test`) exited 0: analysis reported no issues, formatting changed no files, and `+158: All tests passed!`.
7. The trace existence and fixed-string gate exited 0, including the prompt, route, F1–F3, no-failure, paired-description, and stub checks.
8. After tightening the asset test to count both level-0 `+2` receipts, the final `grid_assets/leonard_grid_assets` analysis, format check, and full test rerun exited 0 with no issues, no formatting changes, and `+56: All tests passed!`.

No implementation or validation command failed; no runtime failure signature was produced.

## Paired-description verification

Neither skill description changed because the prompt asks for test authoring, not live driving. `testFrontmatter` and `driveFrontmatter` therefore remain byte-identical to `origin/main`, as do the corresponding frontmatter blocks in both skill files.

## Scope verification

`scripted-device.md and triage.md remain exact stubs`. No level-2, level-3, or level-4 reference was read or modified. No new reference file was added; the references directory still contains exactly its seven pinned files. This trace lives under `grid_assets/leonard_grid_assets/doc/`, outside `extension/`, so it does not ship as consumer skill content.
