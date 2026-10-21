---
status: accepted
date: 2026-10-20
decision-makers:
  - "Nico Spencer"
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: gas-city-pack-drives-in-the-check-with-run-settings-on-the-input-bead
  surfaces:
    - "gc_pack/leonard/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: lenny-guy4.2
  legacy-id: null
---

# The Gas City pack drives in the check, with run settings on the input bead

## Context and Problem Statement

lenny#177 asks for a Gas City pack that runs a live drive as a step in a city's
work. In Gas City 1.5.0 no step type runs a script on its own: a check wraps an
agent step, and the controller runs the check script after the agent closes
the step. That script gets a whitelisted environment: a minimal `PATH`,
`HOME` set to the city, and no model credentials.

## Decision Outcome

* **The drive runs in the check script**
  (`assets/scripts/checks/leonard-drive.sh`), not in the agent's session.
  Ruled by Nico in chat, 2026-10-20. The verdict cannot be produced by an
  agent, and the check's stderr becomes repair context.
* **Run settings ride the input bead** as `leonard.*` metadata. Formula vars,
  carried in step metadata, give the defaults, and the bead wins. Ruled by
  Nico, 2026-10-20.
* **Machine settings never come from a bead (agent).** `leonard_cli` (the
  executable) and `env_file` (sourced for credentials and tool paths) are read
  from step metadata or the environment only, because a bead's writer must
  not choose which program runs, which file is sourced, or where files are
  written (`runs_dir`). Credentials stay in an operator file outside the
  city.
* **The full trajectory is a file, not metadata (agent).** It is written under
  the `runs_dir` machine setting (default `.leonard/runs` in the city), with
  its path on the bead. Not under `$GC_ARTIFACT_DIR`: Gas City deletes a
  workflow's molecule directory when the workflow finalizes, which the e2e
  showed. A digest goes to stderr (Gas City keeps the first 4 KB) and to a
  bead comment.
* **A missing setting exits 64 and records `leonard.verdict=infra` (agent).**
  Nothing was driven, so no attempt should be spent re-running it, and the app
  was not judged.

### Consequences

* Good, because one script serves the `leonard-drive` formula, a check that
  a city composes onto its own implement step, and a gate outside Gas City
  (`LEONARD_INPUT_BEAD`).
* Bad, because each rig must set `leonard_cli` and `env_file` in
  `formula_vars` before a drive can run. The default `leonard_cli` rarely
  resolves on the check `PATH`.
* Bad, because `leonard-drive` spends an agent session on a step whose agent
  only confirms the bead names its settings.
