---
status: accepted
date: 2026-09-02
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a6-one-name-pins-both-self-drive-harnesses-onto-one-model
  surfaces:
    - "packages/leonard_devtools/**"
    - "tool/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: lenny-dvut
  legacy-id: "A6"
---
## A6 (2026-09-02) — `SWIFT_INFER_MODEL` pins BOTH self-drive harnesses, and the receipt records the OBSERVED inner model

**Decision:** one name — `SWIFT_INFER_MODEL` — pins the model for both halves
of the panel self-drive. The OUTER driver reads it at runtime
(`leonard_cli`'s `buildProvider`); the INNER panel, a Flutter web build that
cannot read a runtime environment, reads it at BUILD time through
`--dart-define=SWIFT_INFER_MODEL=<id>`, exposed as
`kDefaultSwiftInferModelId` in
`packages/leonard_devtools/lib/src/panels/provider_config.dart`.
`PANEL_SELFDRIVE_MODEL_ID` remains the scenario's own name for the same value;
`tool/run_panel_selfdrive_scenario.sh` derives each from the other and exits
64 when both are set and disagree. The panel renders its resolved model as one
semantics node identified `prompt.resolvedModel`, and
`tool/verify_panel_selfdrive_receipt.dart` records
`INNER_PANEL_MODEL_RESOLVED` from that node and FAILS the receipt when it
differs from the requested id.
**Why:** the round-9 run (`panel-selfdrive-20260902T050225Z-9764`) drove the
outer harness on `qwen3.8-27b-8bit` while the panel resolved
`qwen3.6-35b-a3b-8bit`; the two loads evicted each other on one swift-infer
server four times in six minutes and closed the outer driver's stream. The
receipt nevertheless claimed 3.8 because it copied the ENV. Extending A5's
principle — a claim about the world is not evidence of it — the inner model
becomes an OBSERVED value.
**Affects (if promoted):** extends A5 from `core.done` to the receipt;
`packages/leonard_devtools`'s provider config + prompt panel,
`tool/run_panel_selfdrive.sh`, `tool/run_panel_selfdrive_scenario.sh`,
`tool/verify_panel_selfdrive_receipt.dart`, and
`packages/leonard_cli/scenarios/leonard_devtools_panel.md`.
**Status:** pending.
