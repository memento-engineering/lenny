---
status: accepted
date: 2026-10-21
decision-makers:
  - "agent"
consulted: []
informed:
  - "Nico Spencer"
register:
  spec: 1
  slug: gas-city-pack-doctor-checks-rebuild-the-drives-environment
  surfaces:
    - "gc_pack/leonard/doctor/**"
    - "gc_pack/leonard/tests/doctor_test.sh"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: lenny-guy4.4
  legacy-id: null
---

# The Gas City pack's doctor checks rebuild the drive's environment

## Context and Problem Statement

lenny#177 asks the leonard pack for doctor checks: `leonard_cli` resolvable,
the env file present, Xcode or the Android SDK, a device to launch on. Gas
City runs a pack doctor script with the full environment of whoever ran
`gc doctor`, plus `GC_CITY_PATH` and `GC_PACK_DIR`. The drive itself runs as
a check script, with a whitelisted environment (a minimal `PATH`, `HOME` set
to the city) and the rig's `env_file` sourced on top. Its machine settings
are per-rig `formula_vars`, which a doctor script is not given.

A doctor that looked at its caller's environment would pass on a machine
where the drive fails. That is the common failure here: `leonard_cli`,
`flutter` and the model credentials are all on the operator's `PATH` and in
their `HOME`, and none of them reach the drive unless the env file puts them
there.

## Decision Outcome

* **Each check rebuilds the drive's environment**: Gas City's check `PATH`
  (the directories of `bd`, `gc`, `dolt` and `jq`, then
  `/usr/local/bin:/usr/bin:/bin`), `HOME` set to the city, then the rig's
  `env_file` sourced with the same semantics as the drive's `in_env`.
* **Machine settings come from the resolved city config**,
  `gc config show --json` run in the city: every rig that imports the pack,
  or sets `leonard_cli` or `env_file` in its `formula_vars`, is checked with
  its own values. With no such rig, the formula's defaults are checked; when
  the config cannot be read, that fallback is said in a `note:` line.
* **Four checks**: `env-file` and `leonard-cli` are errors when they fail,
  because every drive needs them. `platform-tools` and `devices` only warn,
  because a `vm_uri` run attaches to an app that is already running and needs
  neither.
* **No Appium check yet.** The pack's drive has no native channel; the check
  belongs with the slice that adds one.

### Consequences

* Good: a green `gc doctor` means what the drive will see, including the
  case that matters most in practice (tools present for the operator, absent
  for the drive).
* Good: running it found that the drive's city `HOME` hides Flutter's own
  settings, the Android SDK location among them, so an Android device is
  invisible unless the env file sets `ANDROID_HOME`. The README now says so.
* Bad: the checks call `gc config show`, so they depend on its JSON shape
  (Go field names, `Rigs[].FormulaVars`, `Rigs[].Imports`). They read both
  that and the TOML spelling, and fall back to the formula defaults with a
  note if neither is there.
* Bad: the check `PATH` is reconstructed from the doctor's own `PATH`, as Gas
  City derives it from the controller's; a controller started with a
  different `PATH` could still differ.
