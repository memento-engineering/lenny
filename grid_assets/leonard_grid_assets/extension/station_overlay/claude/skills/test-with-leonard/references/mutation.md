# Write tests that kill mutants

Use this reference while writing or reviewing tests when coverage exists but its quality is in question. Lint owns statically decidable patterns such as constructor echo-backs, type-only instantiation checks, and data-only `copyWith` checks. This reference owns the judgement question: does the precondition actually drive the assertion?

## The authoring question

Before writing an assertion, name the single-line source change that would make the test fail.

If you cannot name one, the assertion is decorative. Delete it or sharpen it. Write the proposed change beside the assertion while reviewing; examples are “change the endpoint from `/session` to `/sessions`,” “remove `to.length != 2`,” or “replace the long-press hold with zero.” A test is useful when its setup reaches that line and its observable distinguishes the original from the changed program.

Also ask: could a wrong output still produce the same observable? If a tolerant consumer can forgive the defect, assert the emitted stream or protocol at the producer seam instead of the downstream reaction.

## Checks learned from survivors

These are failure modes to inspect, not predictions that a named file must leak. Their absence from a package is not a pass.

1. **Contract-facing text is behaviour.** Snapshot the complete value that a reader uses to decide: model-facing tool descriptions, `inputSchema`, `required`, defaults, errors, regexes echoed in diagnostics, and log lines. In `leonard_native`, string survivors led to `lenny-i2j6`: the press description omitted three Android keys. In `leonard_contract`, five developer-facing diagnostic strings survived. A type-only exception assertion would not constrain them.
2. **Protocol constants are behaviour.** Assert W3C endpoint paths, session-capability payload keys, namespace regexes, and observable tags such as `via: 'rect-center'` at a fake HTTP or registry boundary. They are hermetic contracts, not device plumbing.
3. **A shipped test double is public API; check that it has its own tests.** `leonard_native`’s fake had 11 survivors, including call recording whose deletion would make downstream `fake.calls` expectations vacuous (`lenny-tkr2`). This is a check, not a universal claim: `leonard_flutter`’s `binding_vm_service_fake.dart` had a dedicated test and killed all 13 mutants.
4. **Probe asymmetry.** For `from == null || from.length != 2 || to == null || to.length != 2`, name and test one breaking change on each half. `leonard_native` exposed separate iOS/Android backend naming, key-vocabulary, and `from`/`to` guard asymmetries in one triage session.
5. **`throwsX` proves a throw type, not a diagnosis.** `throwsArgumentError` left six `ArgumentError.value` field reorderings and message edits alive in `leonard_contract`. Use `throwsA(isA<ArgumentError>().having(...))` to constrain `name`, `invalidValue`, and `message` when callers read them. Tier-1 lint may flag the visible weak matcher; this reference decides which fields are contractual.
6. **Exercise every validator and coercer branch from both sides.** Reject-only namespace tests missed valid digits and underscores. Happy-path JSON tests missed `3.0` coercing to `int`, non-finite doubles, and `bool` supplied where `int` was expected. Give each acceptance, rejection, boundary, and coercion branch a case that reaches it. Paired survivors in duplicated guards are also a design signal to extract one policy.
7. **Drive testability seams, and notice missing seams.** If a constructor accepts an injectable collaborator and no test supplies it, the hole has a name. `ExtensionRegistry` accepted a logger, but five log calls survived because tests never injected one. Ask the inverse when a mutant seems unreachable: “could I kill it if this unit were directly addressable?” A yes means the design needs a seam, not that the mutant is harmless.
8. **Treat class documentation as a test checklist.** For every claimed behaviour, name its test. `ExtensionRegistry` documented four enforced behaviours but tested two; an order claim used `manifest.single`, so one item made the order assertion vacuous. Use enough values for ordering and multiplicity claims to vary.
9. **Assert the generated stream when the consumer is tolerant.** In `leonard_flutter`, 27 of 28 survivors in the sampled files sat in `dispatch.dart`. Gesture tests asserted only that a widget reacted, so wrong interpolation, deltas, pinch arithmetic, and a negative long-press hold still passed through tolerant Flutter recognizers. Capture and assert the pointer stream. The same rule covers serializers read by lenient parsers and retries observed only through eventual success.

## Failure handlers and diagnostic quality

A happy-path trace through recovery does not prove the recovery’s own failure semantics. For every catch block ask: if recovery inside this handler fails, which error reaches the caller? Assert the surviving cause and message.

`lenny-s4mb` was a live example. The published overlay-recovery recipe pinned the exact successful step order, yet an unwrapped dismissal could replace the original obstruction with “no dismissible platform overlay is present.” The implementation already preserved the cause elsewhere. PR #32 shipped the documentation defect; PR #36 fixed it. Swapping wrapped for unwrapped dismissal is the single-line change the order-only test could not kill.

## Verify before excluding

Do not explain a low score away by category. The first `leonard_native` triage proposed excluding strings, test doubles, and device-bound plumbing; every category proved load-bearing. Probe whether the value is observable before calling it inert. Duplicate registration under `dart:developer` looked environmental, but registering twice proved in-process that the first registration landed.

Equivalent mutants are claims about code and require a reachability proof:

- **Essential equivalence** is inert for every reachable input, such as multiplying by one or a redundant check behind a stricter check. Record the proof and move on.
- **Incidental equivalence** comes from code shape: duplicated state encodes one fact, or the reachable domain is narrower than the type. Refactor to expose the policy. In `leonard_contract`, failures and disabled duplicated the strike state, making `>=` and `==` appear identical. An addressable `StrikeCounter` can be driven past the limit and makes the mutant killable (`lenny-xkwn`).

The distinction is proof, not confidence. If direct addressability would kill the mutant, file the refactor instead of excluding it.

Read results per file, never only per package. A file with zero generated mutants is not proven; it may simply contain declarations. Concentration matters: 45 of 55 `leonard_contract` mutants came from one file, and 27 of 28 sampled `leonard_flutter` survivors came from one file.

## Regression-proof bug fixes

Every bug-fix PR ships a test that fails on the parent commit and passes on the fix. Demonstrate both executions in the PR evidence. A green test added after the fix is insufficient unless the parent failure is observed; otherwise it may pin an unrelated property, as the overlay-recovery order test did.

## Calibration receipts

These rules are calibrated against real runs, not asserted as general truths:

- `leonard_native`: 542 mutants, 215 survivors, 60.33% killed, rating C, 22m06s. Survivor triage produced the initial four checks and found `lenny-i2j6`.
- `leonard_contract`: 55 mutants, 28 survivors, 49.09% killed, rating D, 33s. Tests authored from the recorded checks reached 54/55 killed, 98.18%, rating B. The remaining mutant exposed the incidental-equivalence design finding.
- `leonard_flutter`: a targeted, non-random sample of 126 of 777 mutants across five files killed 77.78%, rating C, in 63m. Three of five predictions were wrong: the shipped fake killed 13/13, `budgeted_json.dart` killed 8/8, and `error_ring_buffer.dart` killed 5/5. That contradiction weakened categories from predictions into checks and added the tolerant-consumer rule.

Mutation rewrites source in place. Never analyze, stage, or commit from a tree with a live run. Read the rating honestly; decouple informational CI outcome from score thresholds rather than configuring reports to claim success. Use the installed `tool/leonard/run_mutation.sh` for pure-Dart packages; Flutter mutation remains package-scoped because its observed per-mutant cost was roughly 60 times higher.
