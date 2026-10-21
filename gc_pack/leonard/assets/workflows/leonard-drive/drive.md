Prepare a live Leonard drive of the app for the input bead.

The drive itself is deterministic: Gas City runs it as this step's check
script after you close this step. You do not drive the app.

1. Confirm the input bead says what to drive: a `leonard.scenario` metadata
   value or a description that states the scenario, and either
   `leonard.vm_uri` (an app already running with Leonard installed) or
   `leonard.device` plus `leonard.target` (Leonard launches the app from this
   work directory).
2. If something is missing, say what in a note on the input bead, then close
   this step anyway. The check will report the missing setting.
3. Close this step with `gc.outcome=pass`. Make no code changes.

The check writes `leonard.verdict` (`pass`, `fail` or `infra`),
`leonard.reason` and `leonard.trajectory` to the input bead, and adds a
comment with the last turns of the drive.
