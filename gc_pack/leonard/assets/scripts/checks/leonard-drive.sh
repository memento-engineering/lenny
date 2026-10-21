#!/usr/bin/env bash
set -euo pipefail

# Leonard live-drive check.
#
# Drives the running app toward the input bead's scenario with leonard_cli,
# then records the verdict on that bead. Exit status is the Gas City check
# protocol:
#   0   pass   - the model reached the goal
#   1   fail   - Leonard drove the app and the goal was not met
#   75  infra  - no judgement about the app (no attach, model unreachable,
#                gc unreadable). Gas City 1.5.0 fails a formula's check on 75
#                like any nonzero exit; leonard.verdict=infra says why
#   64  config - the bead or formula is missing a setting; nothing was driven
#
# Which bead: $GC_BEAD_ID is the checked step's bead. Its workflow root
# (gc.root_bead_id) names the input convoy (gc.input_convoy_id), whose single
# child is the bead that was slung. Without a convoy the root, then the step
# bead itself, is the input. $LEONARD_INPUT_BEAD names it directly, which is
# how a gate outside Gas City calls this script.
#
# Settings: the input bead's leonard.<key> metadata wins, then the step's
# leonard.<key> metadata (the formula vars), then the default. The machine
# settings leonard_cli, env_file and runs_dir are read from the Gas City step
# ($GC_BEAD_ID, where the formula vars land) and the environment only, never
# from the input bead: a bead must not choose which program runs, which file
# is sourced, or where files are written. Outside Gas City there is no step,
# so they come from the environment alone.
#
# The env file is sourced in a subshell, only around the leonard_cli lookup
# and the drive, so it cannot change this script's own variables.
#
# stderr is repair context (Gas City keeps its first 4 KB), so leonard_cli's
# own output goes to leonard.log in the run directory, and stderr carries
# only the verdict line, the turn digest and the trajectory path.

EX_FAIL=1
EX_CONFIG=64
EX_INFRA=75

say() {
  printf 'leonard-drive: %s\n' "$*" >&2
}

INPUT_ID=""
RECORDING=""

infra() {
  # Record the verdict once the input bead is known, so a bead never keeps
  # an earlier attempt's verdict past an infra exit. RECORDING stops a
  # failed record from recursing.
  say "infra: $*"
  if [ -n "$INPUT_ID" ] && [ -z "$RECORDING" ]; then
    record infra "$*"
  fi
  exit "$EX_INFRA"
}

command -v gc >/dev/null 2>&1 || infra "gc is required on PATH"
command -v python3 >/dev/null 2>&1 || infra "python3 is required on PATH"

GC_ERR="$(mktemp)"
trap 'rm -f "$GC_ERR"' EXIT INT TERM HUP

gc_read() {
  # gc_read <args...> -> stdout of gc, or exit 75 naming the failed command
  gc "$@" 2>"$GC_ERR" ||
    infra "gc $* failed: $(tail -c 400 "$GC_ERR" | tr '\n' ' ')"
}

json_value() {
  # json_value <json> <path> -> the string at <path>, or empty. <path> is
  # metadata.<key>, a top-level field, or children.single (the id of the only
  # child of a `gc convoy status --json`). bd returns a numeric-looking value
  # as a JSON number, so numbers and booleans read as their text. An
  # unresolved {{var}} placeholder, which gc leaves in metadata when no var
  # supplied it, reads as empty.
  printf '%s' "$1" | python3 -c '
import json
import re
import sys

path = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
if isinstance(data, list):
    data = data[0] if data else {}
if not isinstance(data, dict):
    raise SystemExit(0)
if path == "children.single":
    children = data.get("children") or []
    value = children[0].get("id", "") if len(children) == 1 else ""
elif path.startswith("metadata."):
    metadata = data.get("metadata") or {}
    value = metadata.get(path[len("metadata."):], "") if isinstance(metadata, dict) else ""
else:
    value = data.get(path, "")
if isinstance(value, bool):
    value = "true" if value else "false"
elif isinstance(value, (int, float)):
    value = str(value)
if not isinstance(value, str) or re.fullmatch(r"\{\{[^{}]+\}\}", value.strip()):
    value = ""
print(value, end="")
' "$2"
}

record() {
  # record <verdict> <reason> [<run-dir>] -> leonard.* metadata on the input bead
  local reason
  reason="$(printf '%s' "$2" | tr '`' "'")"
  RECORDING=1
  local args=(bd update "$INPUT_ID" --set-metadata "leonard.verdict=$1" --set-metadata "leonard.reason=$reason")
  if [ -n "${3:-}" ]; then
    args+=(--set-metadata "leonard.trajectory=$3/trajectory.jsonl" --set-metadata "leonard.run_dir=$3")
  fi
  gc "${args[@]}" >/dev/null 2>"$GC_ERR" ||
    infra "recording the verdict on $INPUT_ID failed: $(tail -c 400 "$GC_ERR" | tr '\n' ' ')"
}

# ----- resolve the step and input beads ---------------------------------
STEP_ID="${GC_BEAD_ID:-${LEONARD_INPUT_BEAD:-}}"
[ -n "$STEP_ID" ] || {
  say "config: GC_BEAD_ID (or LEONARD_INPUT_BEAD) is required"
  exit "$EX_CONFIG"
}
STEP_JSON="$(gc_read bd show "$STEP_ID" --json)"
# Machine settings are read only from a Gas City step, never from a bead
# named by LEONARD_INPUT_BEAD.
MACHINE_JSON=""
[ -z "${GC_BEAD_ID:-}" ] || MACHINE_JSON="$STEP_JSON"

if [ -z "${LEONARD_INPUT_BEAD:-}" ]; then
  ROOT_ID="$(json_value "$STEP_JSON" metadata.gc.root_bead_id)"
  ROOT_JSON="$STEP_JSON"
  if [ -n "$ROOT_ID" ] && [ "$ROOT_ID" != "$STEP_ID" ]; then
    ROOT_JSON="$(gc_read bd show "$ROOT_ID" --json)"
  fi
  CONVOY_ID="$(json_value "$ROOT_JSON" metadata.gc.input_convoy_id)"
  if [ -n "$CONVOY_ID" ]; then
    CONVOY_JSON="$(gc_read convoy status "$CONVOY_ID" --json)"
    INPUT_ID="$(json_value "$CONVOY_JSON" children.single)"
  fi
  [ -n "$INPUT_ID" ] || INPUT_ID="${ROOT_ID:-$STEP_ID}"
  INPUT_JSON="$STEP_JSON"
  if [ "$INPUT_ID" != "$STEP_ID" ]; then
    INPUT_JSON="$(gc_read bd show "$INPUT_ID" --json)"
  fi
else
  INPUT_ID="$LEONARD_INPUT_BEAD"
  INPUT_JSON="$STEP_JSON"
  if [ "$INPUT_ID" != "$STEP_ID" ]; then
    INPUT_JSON="$(gc_read bd show "$INPUT_ID" --json)"
  fi
fi

config_error() {
  say "config: $* (input bead $INPUT_ID)"
  record infra "config: $*"
  exit "$EX_CONFIG"
}

setting() {
  # setting <key> [<default>] -> input bead, then step, then default
  local value
  value="$(json_value "$INPUT_JSON" "metadata.leonard.$1")"
  [ -n "$value" ] || value="$(json_value "$STEP_JSON" "metadata.leonard.$1")"
  printf '%s' "${value:-${2:-}}"
}

machine_setting() {
  # machine_setting <key> <env-value> [<default>] -> Gas City step, then env,
  # then default
  local value
  value="$(json_value "$MACHINE_JSON" "metadata.leonard.$1")"
  printf '%s' "${value:-${2:-${3:-}}}"
}

# ----- read the run settings ----------------------------------------------
SCENARIO="$(setting scenario)"
[ -n "$SCENARIO" ] || SCENARIO="$(json_value "$INPUT_JSON" description)"
[ -n "$SCENARIO" ] || config_error "no scenario: set leonard.scenario or a description"

VM_URI="$(setting vm_uri)"
DEVICE="$(setting device)"
TARGET="$(setting target)"
if [ -z "$VM_URI" ] && { [ -z "$DEVICE" ] || [ -z "$TARGET" ]; }; then
  config_error "nothing to drive: set leonard.vm_uri, or leonard.device and leonard.target"
fi

LEONARD_CLI_SETTING="$(machine_setting leonard_cli "${LEONARD_CLI:-}" leonard_cli)"
ENV_FILE="$(machine_setting env_file "${LEONARD_ENV_FILE:-}")"
[ -z "$ENV_FILE" ] || [ -f "$ENV_FILE" ] || infra "env_file not found: $ENV_FILE"

in_env() {
  # in_env <command...> -> run the command in a subshell with the env file's
  # variables exported. Unset variables in the file expand empty, as in an
  # interactive shell; a file that fails to load fails the command.
  (
    if [ -n "$ENV_FILE" ]; then
      set +u -a
      # shellcheck disable=SC1090
      . "$ENV_FILE" || exit 1
      set -u +a
    fi
    "$@"
  )
}

in_env true 2>"$GC_ERR" ||
  infra "env_file failed to load: $ENV_FILE: $(tail -c 300 "$GC_ERR" | tr '\n' ' ')"
LEONARD_CLI_BIN="$(in_env command -v "$LEONARD_CLI_SETTING" 2>/dev/null)" ||
  infra "leonard_cli not found: $LEONARD_CLI_SETTING (set the leonard_cli var to an absolute path)"

WORK_DIR="${GC_WORK_DIR:-$PWD}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
# Not $GC_ARTIFACT_DIR: Gas City deletes a workflow's molecule directory when
# the workflow finalizes, and the trajectory must outlive it.
DEFAULT_RUNS_DIR="${GC_CITY_PATH:+$GC_CITY_PATH/.leonard/runs}"
RUNS_DIR="$(machine_setting runs_dir "${LEONARD_RUNS_DIR:-}" "${DEFAULT_RUNS_DIR:-$WORK_DIR/.leonard/runs}")"
RUN_DIR="$RUNS_DIR/$INPUT_ID-${GC_ITERATION:-0}-$STAMP"
mkdir -p "$RUN_DIR" 2>"$GC_ERR" ||
  infra "cannot create the run directory $RUN_DIR: $(tail -c 200 "$GC_ERR" | tr '\n' ' ')"
printf '%s\n' "$SCENARIO" >"$RUN_DIR/goal.txt"

ARGS=(
  --goal-file "$RUN_DIR/goal.txt"
  --output "$RUN_DIR/trajectory.jsonl"
  --summary-json "$RUN_DIR/summary.json"
  --gate-exit-codes
  --model "$(setting model claude)"
  --wall-clock-minutes "$(setting wall_clock_minutes 15)"
)
if [ -n "$VM_URI" ]; then
  ARGS+=(--vm-uri "$VM_URI")
else
  ARGS+=(--launch -d "$DEVICE" -t "$TARGET")
fi
add_flag() {
  # add_flag <flag> <key> -> append "<flag> <value>" when the setting is set
  local value
  value="$(setting "$2")"
  if [ -n "$value" ]; then
    ARGS+=("$1" "$value")
  fi
}
add_flag --model-id model_id
add_flag --harness harness
add_flag --extensions extensions
add_flag --done-evidence-pattern done_evidence
add_flag --done-reason-pattern done_reason

# ----- drive -------------------------------------------------------------
set +e
drive() {
  # drive <work-dir> <leonard_cli> <args...>
  cd "$1" && shift && exec "$@"
}
in_env drive "$WORK_DIR" "$LEONARD_CLI_BIN" "${ARGS[@]}" >"$RUN_DIR/leonard.log" 2>&1 </dev/null
DRIVE_EXIT=$?
set -e

SUMMARY_JSON=""
[ -f "$RUN_DIR/summary.json" ] && SUMMARY_JSON="$(cat "$RUN_DIR/summary.json")"
VERDICT="$(json_value "$SUMMARY_JSON" verdict)"
REASON="$(json_value "$SUMMARY_JSON" reason)"
case "$DRIVE_EXIT:$VERDICT" in
  0:pass | 1:fail | 75:infra) ;;
  *)
    VERDICT=infra
    REASON="leonard_cli exited $DRIVE_EXIT${REASON:+: $REASON}; see $RUN_DIR/leonard.log"
    ;;
esac
[ -n "$REASON" ] || REASON="see $RUN_DIR/leonard.log"

DIGEST="$(printf '%s' "$SUMMARY_JSON" | python3 -c '
import json
import sys

try:
    digest = json.load(sys.stdin).get("digest") or []
except Exception:
    digest = []
print("\n".join(line for line in digest if isinstance(line, str)), end="")
')"

# ----- record and report -------------------------------------------------
record "$VERDICT" "$REASON" "$RUN_DIR"
{
  printf 'leonard-drive %s (attempt %s): %s\n' "$VERDICT" "${GC_ITERATION:-1}" "$REASON"
  if [ -n "$DIGEST" ]; then
    printf '\nLast turns:\n%s\n' "$DIGEST"
  fi
  printf '\nTrajectory: %s\n' "$RUN_DIR/trajectory.jsonl"
} | tr '`' "'" >"$RUN_DIR/comment.txt"
gc bd comments add "$INPUT_ID" -f "$RUN_DIR/comment.txt" >/dev/null 2>"$GC_ERR" ||
  say "warning: could not comment on $INPUT_ID: $(tail -c 200 "$GC_ERR" | tr '\n' ' ')"

say "$VERDICT — $REASON"
if [ -n "$DIGEST" ]; then
  printf '%s\n' "$DIGEST" >&2
fi
say "trajectory: $RUN_DIR/trajectory.jsonl"

case "$VERDICT" in
  pass) exit 0 ;;
  fail) exit "$EX_FAIL" ;;
  *) exit "$EX_INFRA" ;;
esac
