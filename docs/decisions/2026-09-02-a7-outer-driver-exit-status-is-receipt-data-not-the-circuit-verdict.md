---
status: accepted
date: 2026-09-02
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a7-outer-driver-exit-status-is-receipt-data-not-the-circuit-verdict
  surfaces:
    - "grid_assets/leonard_grid_assets/**"
    - "tool/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: lenny-f7nx.6
  legacy-id: "A7"
---
## A7 (2026-09-02) — the outer driver's exit status is receipt DATA; the verifier is the circuit's verdict

**Decision:** the `selfdrive` circuit's `outer-driver` step wraps the driver so
the shell always exits zero and writes the driver's own status to
`<run-dir>/driver.status`; the terminal `verify` step reads that file and
records it as `SCENARIO_EXIT_STATUS`, and the circuit's pass/fail is the
VERIFIER's exit status alone. The station receipt and
`tool/run_panel_selfdrive_scenario.sh`'s manual receipt carry one field set:
`PANEL_SELFDRIVE_ROUND`, `RECEIPT_PATH`, `PANEL_SELFDRIVE_RECEIPT`,
`RUN_HEAD`, `SCENARIO_EXIT_STATUS`, `VERIFIER_EXIT_STATUS`,
`FAILING_ASSERTION`, `FURTHEST_POINT`, `TURN_COUNT`, `STOP_OBSERVED`,
`OUTER_DRIVER_MODEL_ID`, `INNER_PANEL_MODEL_ID`.
**Why:** `verify` `dependsOn` `outer-driver`, so a failing driver stopped the
circuit at the step BEFORE the one that writes the receipt — the round-9 mode
(`ClientException` on `/v1/messages`, then timeouts) would have produced no
receipt at all from the station path. A negative receipt is the deliverable of
a self-drive round; withholding it on failure is the one outcome the epic
cannot use.
**Affects:** extends A6's observed-value principle from the inner model id to
the run's own outcome; `grid_assets/leonard_grid_assets`'s `outer_driver.dart`
and `selfdrive_verify.dart`, and `tool/run_panel_selfdrive_scenario.sh`.
