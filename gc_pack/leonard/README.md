# leonard: a Gas City pack

A live-drive integration check for Gas City cities. Leonard attaches to a
running Flutter or Dart app over the VM service, drives it toward a scenario
with a model, and records whether the app got there. Unit and widget tests do
not show that a feature works in the running app; this does.

Requires Gas City 1.5.0 or later (pack schema 2, formulas v2) and
`leonard_cli` 0.4.2 or later (`--gate-exit-codes`). Verified against Gas City
1.5.0 by `tool/gc_pack_e2e.sh`.

## Import

```toml
# city.toml
[[rigs]]
name = "app"

[rigs.imports.leonard]
source = "https://github.com/memento-engineering/lenny/tree/main/gc_pack/leonard"
```

Then set the machine settings once per rig. Check scripts run with a minimal
`PATH` and with `HOME` set to the city, so neither the model credentials nor a
pub-installed `leonard_cli` is visible to them:

```toml
[rigs.formula_vars]
leonard_cli = "/Users/you/.pub-cache/bin/leonard_cli"
env_file = "/Users/you/.config/leonard/gc.env"
```

`env_file` is sourced, in a subshell, around each drive, so it is where
credentials and tool paths go. A file that fails to load is an infra
verdict. Keep it outside the city directory (the city is listable and backed
up):

```sh
# ~/.config/leonard/gc.env
PATH=/opt/homebrew/bin:/Users/you/flutter/bin:$PATH
PUB_CACHE=/Users/you/.pub-cache
ANTHROPIC_API_KEY=sk-ant-...
# For device/target runs on Android: the drive's HOME is the city, so Flutter
# cannot read the SDK location from your own Flutter settings.
# ANDROID_HOME=/Users/you/Library/Android/sdk
# or, to run on a ChatGPT subscription through --harness codex:
# CODEX_HOME=/Users/you/.codex
```

Then run `gc doctor` (see [Doctor checks](#doctor-checks)).

## Run a drive against a bead

Describe the scenario on the bead, say where the app is, and sling it:

```sh
gc bd update app-123 \
  --set-metadata 'leonard.scenario=Sign in as demo@example.com and open Settings' \
  --set-metadata 'leonard.vm_uri=ws://127.0.0.1:54321/abc=/ws'
gc sling app/<agent> app-123 --on leonard-drive
```

The `leonard-drive` formula has one step. Its agent only confirms the bead
names a scenario and a target, then closes the step. The drive itself runs as
the step's check script, deterministically, after that.

## Settings

Run settings ride the input bead as `leonard.*` metadata. The formula's vars
supply defaults, and the bead wins:

| Key | Meaning | Formula var |
|---|---|---|
| `leonard.scenario` | The goal to drive toward. Falls back to the bead description. | — |
| `leonard.vm_uri` | VM service URI of an app already running with Leonard installed. | — |
| `leonard.device`, `leonard.target` | Instead of `vm_uri`: Leonard runs `flutter run -d <device> -t <target>` from the work directory and drives that. | — |
| `leonard.model` | Model tier: `claude`, `openai` or `qwen-mlx`. | `model` (`claude`) |
| `leonard.model_id` | Exact model id for the tier. | `model_id` |
| `leonard.harness` | ACP harness instead of the tier: `codex` or `copilot`. | `harness` |
| `leonard.wall_clock_minutes` | Whole-drive budget. | `wall_clock_minutes` (`15`) |
| `leonard.extensions` | Extension namespaces to enable, e.g. `router,riverpod`. | — |
| `leonard.done_evidence` | Regex an observed label or value must match before `core.done` is accepted. Use it to stop a model from declaring success early. | — |
| `leonard.done_reason` | Regex the `core.done` reason must match. | — |

`leonard_cli`, `env_file` and `runs_dir` are machine settings: they are read
from the formula vars (or the `LEONARD_CLI`, `LEONARD_ENV_FILE` and
`LEONARD_RUNS_DIR` environment), never from the bead, because a bead must not
choose which program runs, which file is sourced, or where files land.
Outside Gas City (`LEONARD_INPUT_BEAD`) they come from the environment
alone.

## What the check writes

On the input bead:

- `leonard.verdict`: `pass`, `fail` or `infra`
- `leonard.reason`: one line, e.g. `budget exhausted after 50 turns without reaching the goal`
- `leonard.trajectory`: the full trajectory JSONL; `leonard.run_dir` holds it
  with the captured frames, the run summary and `leonard.log`
- a comment with the verdict and the last turns of the drive, one line each

Run directories go under the `runs_dir` var, by default `.leonard/runs/` in
the city. Not under `$GC_ARTIFACT_DIR`: Gas City deletes a workflow's
molecule directory, artifacts included, when the workflow finalizes. Nothing
prunes `runs_dir`; the operator owns retention.

## Exit codes

| Exit | Meaning |
|---|---|
| 0 | pass: the model reached the goal |
| 1 | fail: Leonard drove the app and the goal was not met (budget exhausted, the app went away mid-drive, a golden mismatch) |
| 75 | infra: no judgement about the app (no attach, model unreachable or misconfigured, the model could not produce a valid action, gc unreadable) |
| 64 | config: the bead or formula is missing a setting, so nothing was driven. Recorded as `leonard.verdict=infra`; in Gas City 1.5.0 it fails the attempt like any nonzero exit |

Every exit records `leonard.verdict` once the input bead is known, so a bead
never keeps an earlier attempt's verdict.

**Exit 75 in Gas City 1.5.0.** The formula spec says a check's exit 75 is
re-run without spending an attempt. That holds only for standalone check
beads: a formula's `[steps.check]` runs on the ralph path, which treats 75 like
any other failure, so the workflow fails. `leonard.verdict=infra` on the bead
is what tells an infrastructure failure from a real one. The e2e pins this
behaviour and will flag a Gas City release that changes it.

Gas City keeps the first 4 KB of a failing check's stderr as repair context
for the next attempt. The check's stderr is the verdict line, the turn digest
and the trajectory path, so the next coding-agent attempt sees where the drive
got stuck.

## Compose the check into your own formula

The check script works on any checked step, so a city can verify its own
implement step with a live drive. A failed drive then sends the coding agent
back with the digest as repair context:

```toml
[vars.leonard_cli]
default = "leonard_cli"

[vars.env_file]
default = ""

[[steps]]
id = "implement"
title = "Implement the feature"
metadata = { "leonard.leonard_cli" = "{{leonard_cli}}", "leonard.env_file" = "{{env_file}}" }

[steps.check]
max_attempts = 3

[steps.check.check]
mode = "exec"
path = "../assets/scripts/checks/leonard-drive.sh"
timeout = "30m"
```

**The agent under check can weaken this gate.** It can write the input bead's
`leonard.*` run settings, which outrank the formula, and its own step bead's
metadata, where `leonard_cli` and `env_file` are read. Compose the check only
where the coding agent is cooperative; a gate it cannot tamper with is
`lenny-guy4.6`.

## Outside Gas City

A gate that is not a Gas City check can run the script directly. Name the bead
and the machine settings in the environment:

```sh
LEONARD_INPUT_BEAD=app-123 \
LEONARD_CLI=/Users/you/.pub-cache/bin/leonard_cli \
LEONARD_ENV_FILE=/Users/you/.config/leonard/gc.env \
  gc_pack/leonard/assets/scripts/checks/leonard-drive.sh
```

Outside Gas City, runs land in `.leonard/runs/` under the working directory
unless `LEONARD_RUNS_DIR` says otherwise. Or skip the pack and call
`leonard_cli --gate-exit-codes --summary-json <path>` yourself.

## Doctor checks

`gc doctor` runs four checks from this pack. Each one rebuilds the
environment the drive actually gets, a Gas City check's minimal `PATH` and
`HOME` set to the city with the rig's `env_file` sourced on top, so a check
passes only if the drive would see the same thing. Each rig that imports the
pack, or sets `leonard_cli` or `env_file` in its `formula_vars`, is checked
with its own settings, read from `gc config show --json`.

| Check | Error (exit 2) | Warning (exit 1) |
|---|---|---|
| `leonard:env-file` | the `env_file` is missing or fails to load | no `env_file` is set (no credentials, minimal `PATH`), or it is inside the city |
| `leonard:leonard-cli` | `leonard_cli` does not resolve on the drive's `PATH`, or predates `--gate-exit-codes` (0.4.2) | — |
| `leonard:platform-tools` | — | no `flutter`, or neither `xcodebuild` nor `adb`, or no Xcode selected |
| `leonard:devices` | — | `flutter devices` sees nothing to launch on |

`platform-tools` and `devices` only warn: a `vm_uri` run attaches to an app
that is already running and needs neither. `gc doctor --verbose` lists what
each check found, rig by rig, including every device Flutter can launch on.

## Not yet

- Building and launching the app at a given commit. Today a device/target run
  builds whatever is checked out in the step's work directory. Which commit to
  build, and who owns that checkout, is an open design question
  (`lenny-guy4.4`).
- A doctor check for Appium. The pack's drive has no native channel yet; the
  check belongs with it.

## Tests

```sh
gc_pack/leonard/tests/leonard_drive_test.sh   # the check script, against fakes (CI)
gc_pack/leonard/tests/doctor_test.sh          # the doctor checks, against fakes (CI)
tool/gc_pack_e2e.sh                           # a throwaway Gas City 1.5.0 city, on demand
```

The e2e builds a private city (pinned gc and bd binaries, its own `GC_HOME`
and Dolt servers, the foreground controller, never the machine supervisor),
boots the sample app on macOS, and slings an infra, a pass and a fail
scenario through `leonard-drive` with a scripted stub agent. It drives with
local qwen by default (`LEONARD_GC_E2E_MODEL` picks another tier) and takes
about 15 minutes.
