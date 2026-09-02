#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/tool/run_panel_selfdrive_scenario.sh"
[[ -x "$SCRIPT" ]] || {
  printf 'run_panel_selfdrive_scenario_test: script is not executable: %s\n' "$SCRIPT" >&2
  exit 1
}
bash -n "$SCRIPT"

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/run-panel-selfdrive-scenario-test.XXXXXX")"
FAKE_HARNESS="$TEST_ROOT/fake_harness"
FAKE_DRIVER="$TEST_ROOT/fake_driver"
FAKE_BD="$TEST_ROOT/fake_bd"
cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

cat >"$FAKE_HARNESS" <<'FAKE_HARNESS'
#!/usr/bin/env bash
set -euo pipefail
: >"$FAKE_STATE_DIR/harness_started"
mkdir -p "$PANEL_SELFDRIVE_ARTIFACT_DIR"
printf '%s\n' 'sample app fixture log' \
  >"$PANEL_SELFDRIVE_ARTIFACT_DIR/sample_app.log"
if [[ "${FAKE_PANEL_ENDPOINT_LEAK:-0}" == 1 ]]; then
  printf '%s\n' "$SWIFT_INFER_ENDPOINT" \
    >"$PANEL_SELFDRIVE_ARTIFACT_DIR/panel.log"
else
  printf '%s\n' 'panel fixture log' \
    >"$PANEL_SELFDRIVE_ARTIFACT_DIR/panel.log"
fi
printf '%s\n' 'ws://127.0.0.1:7000/panel=/ws'
trap 'exit 0' INT TERM
while :; do
  sleep 0.1
done
FAKE_HARNESS

cat >"$FAKE_DRIVER" <<'FAKE_DRIVER'
#!/usr/bin/env bash
set -euo pipefail
: >"$FAKE_STATE_DIR/driver_started"
printf '%s\n' "$@" >"$FAKE_STATE_DIR/driver_args"
output=''
goal_file=''
probe_artifact=''
while (( $# > 0 )); do
  case "$1" in
    --output)
      output="$2"
      shift 2
      ;;
    --goal-file)
      goal_file="$2"
      shift 2
      ;;
    --probe-artifact)
      probe_artifact="$2"
      shift 2
      ;;
    --core-budget-bytes)
      printf '%s\n' "$2" >"$FAKE_STATE_DIR/core_budget_bytes"
      shift 2
      ;;
    *) shift ;;
  esac
done
[[ -n "$output" && -n "$goal_file" && -n "$probe_artifact" ]]
cp -f "$goal_file" "$FAKE_STATE_DIR/goal_file_content"
printf '%s\n' \
  '{"isolate_id":"panel-1","handshake":{"contractVersion":"2"},"observation":{"type":"Response","value":{"semantics":[]}}}' \
  >"$probe_artifact"
model_value="${FAKE_RESOLVED_MODEL_ID:-${PANEL_SELFDRIVE_MODEL_ID:-unset}}"
cat >"$output" <<'JSONL'
{"type":"turn","index":0,"observation":{"core":{"nodes":[]}},"proposed_action":{"tool":"core.enter_text","args":{"text":"${SWIFT_INFER_ENDPOINT}"}}}
{"type":"turn","index":1,"observation":{"core":{"nodes":[]}},"proposed_action":{"tool":"core.enter_text","args":{"text":"${SWIFT_INFER_AGENT_TOKEN}"}}}
{"type":"turn","index":2,"observation":{"core":{"nodes":[]}},"proposed_action":{"tool":"core.enter_text","args":{"text":"${PANEL_SELFDRIVE_MODEL_ID}"}}}
JSONL
cat >>"$output" <<JSONL
{"type":"turn","index":3,"observation":{"core":{"nodes":[{"label":"OK (2 models)"},{"label":"Stop"},{"identifier":"prompt.resolvedModel","label":"Resolved model","value":"$model_value"}]}},"proposed_action":{"tool":"core.tap","args":{}}}
JSONL
cat >>"$output" <<'JSONL'
{"type":"turn","index":4,"observation":{"core":{"nodes":[{"label":"#0 core.done()"},{"label":"Proposed action"},{"value":"core.done()"}]}},"proposed_action":{"tool":"core.tap","args":{}}}
{"type":"turn","index":5,"observation":{"core":{"nodes":[{"label":"Start","actions":["tap"],"state":[]}]}},"proposed_action":{"tool":"core.done","args":{"reason":"panel smoke passed: inner turn 0 tool core.done"}}}
JSONL
if [[ "${FAKE_DRIVER_LEAK:-0}" == 1 ]]; then
  printf '%s\n' "$SWIFT_INFER_AGENT_TOKEN" >&2
fi
if [[ "${FAKE_DRIVER_FAIL:-0}" == 1 ]]; then
  printf '%s\n' 'driver fixture failure' >&2
  exit 3
fi
FAKE_DRIVER

cat >"$FAKE_BD" <<'FAKE_BD'
#!/usr/bin/env bash
set -euo pipefail
command_name="${1:-}"
shift || true
case "$command_name" in
  update)
    note=''
    while (( $# > 0 )); do
      case "$1" in
        --append-notes)
          note="$2"
          shift 2
          ;;
        *) shift ;;
      esac
    done
    if [[ "${FAKE_BD_DROP_APPEND:-0}" != 1 ]]; then
      printf '%s\n' "$note" >>"$FAKE_STATE_DIR/bd_notes"
    fi
    ;;
  show)
    if [[ -f "$FAKE_STATE_DIR/bd_notes" ]]; then
      cat "$FAKE_STATE_DIR/bd_notes"
    fi
    ;;
  *)
    printf 'fake_bd: unsupported command: %s\n' "$command_name" >&2
    exit 64
    ;;
esac
FAKE_BD

chmod +x "$FAKE_HARNESS" "$FAKE_DRIVER" "$FAKE_BD"

run_dir_from_stderr() {
  sed -n 's/^PANEL_SELFDRIVE_RUN_DIR=//p' "$1" | tail -n 1
}

HAPPY_STATE="$TEST_ROOT/happy-state"
mkdir -p "$HAPPY_STATE"
env -u PANEL_SELFDRIVE_MODEL_ID -u SWIFT_INFER_MODEL \
SWIFT_INFER_ENDPOINT='https://swift.example' \
SWIFT_INFER_AGENT_TOKEN='fixture-secret-never-written' \
FAKE_STATE_DIR="$HAPPY_STATE" \
PANEL_SELFDRIVE_HARNESS="$FAKE_HARNESS" \
PANEL_SELFDRIVE_DRIVER_BIN="$FAKE_DRIVER" \
PANEL_SELFDRIVE_BD_BIN="$FAKE_BD" \
PANEL_SELFDRIVE_OUTPUT_ROOT="$HAPPY_STATE/output" \
  "$SCRIPT" macos >"$HAPPY_STATE/stdout" 2>"$HAPPY_STATE/stderr"
HAPPY_RUN_DIR="$(run_dir_from_stderr "$HAPPY_STATE/stderr")"
grep -F 'TRAJECTORY_PATH=' "$HAPPY_STATE/stdout" >/dev/null
grep -Fx 'OBSERVED_TURN_INDEX=0' "$HAPPY_STATE/stdout" >/dev/null
grep -Fx 'OBSERVED_TURN_TOOL=core.done' "$HAPPY_STATE/stdout" >/dev/null
grep -Fx 'PROMPT_FORM=enabled' "$HAPPY_STATE/stdout" >/dev/null
grep -Fx 'CAPTURED_OUTPUT_SECRET_SCAN=clean' "$HAPPY_STATE/stdout" >/dev/null
grep -Fx -- '--goal-file' "$HAPPY_STATE/driver_args" >/dev/null
grep -Fx -- '--action-env' "$HAPPY_STATE/driver_args" >/dev/null
grep -Fx -- '--probe-artifact' "$HAPPY_STATE/driver_args" >/dev/null
grep -Fx '131072' "$HAPPY_STATE/core_budget_bytes" >/dev/null
[[ ! -e "$HAPPY_STATE/probe_args" ]]
[[ -f "$HAPPY_STATE/driver_started" ]]
[[ -f "$HAPPY_RUN_DIR/bead.note" ]]
[[ -f "$HAPPY_RUN_DIR/bead.readback" ]]
SCRIPT_ROUND_MARKER="$(sed -n "s/^ROUND_MARKER='\(PANEL_SELFDRIVE_ROUND=[0-9]*\)'\$/\1/p" \
  "$SCRIPT" | head -n 1)"
[[ -n "$SCRIPT_ROUND_MARKER" ]]
grep -Fx "$SCRIPT_ROUND_MARKER" "$HAPPY_STATE/bd_notes" >/dev/null
grep -E '^RUN_HEAD=[0-9a-f]{40}$' "$HAPPY_STATE/bd_notes" >/dev/null
grep -Fx 'PANEL_SELFDRIVE_RECEIPT=passed' "$HAPPY_STATE/bd_notes" >/dev/null
grep -Fx 'INNER_PANEL_MODEL_REQUESTED=qwen3.6-35b-a3b-8bit' \
  "$HAPPY_STATE/stdout" >/dev/null
grep -Fx 'INNER_PANEL_MODEL_RESOLVED=qwen3.6-35b-a3b-8bit' \
  "$HAPPY_STATE/stdout" >/dev/null
grep -Fx 'INNER_PANEL_MODEL_ID=qwen3.6-35b-a3b-8bit' \
  "$HAPPY_STATE/bd_notes" >/dev/null
grep -Fx 'OUTER_DRIVER_MODEL_ID=qwen3.6-35b-a3b-8bit' \
  "$HAPPY_STATE/bd_notes" >/dev/null
grep -F 'SWIFT_INFER_AGENT_TOKEN' "$HAPPY_STATE/goal_file_content" >/dev/null
! grep -R -F 'fixture-secret-never-written' "$HAPPY_STATE/output"

run_missing_case() {
  local missing_name="$1"
  local case_dir="$TEST_ROOT/missing-$missing_name"
  local status
  mkdir -p "$case_dir"
  set +e
  if [[ "$missing_name" == SWIFT_INFER_ENDPOINT ]]; then
    env -u SWIFT_INFER_ENDPOINT \
      SWIFT_INFER_AGENT_TOKEN='fixture-token' \
      FAKE_STATE_DIR="$case_dir" \
      PANEL_SELFDRIVE_HARNESS="$FAKE_HARNESS" \
      PANEL_SELFDRIVE_DRIVER_BIN="$FAKE_DRIVER" \
      PANEL_SELFDRIVE_BD_BIN="$FAKE_BD" \
      PANEL_SELFDRIVE_OUTPUT_ROOT="$case_dir/output" \
      "$SCRIPT" macos >"$case_dir/stdout" 2>"$case_dir/stderr"
  else
    env -u SWIFT_INFER_AGENT_TOKEN \
      SWIFT_INFER_ENDPOINT='https://swift.example' \
      FAKE_STATE_DIR="$case_dir" \
      PANEL_SELFDRIVE_HARNESS="$FAKE_HARNESS" \
      PANEL_SELFDRIVE_DRIVER_BIN="$FAKE_DRIVER" \
      PANEL_SELFDRIVE_BD_BIN="$FAKE_BD" \
      PANEL_SELFDRIVE_OUTPUT_ROOT="$case_dir/output" \
      "$SCRIPT" macos >"$case_dir/stdout" 2>"$case_dir/stderr"
  fi
  status=$?
  set -e
  [[ "$status" == 64 ]]
  grep -F "$missing_name" "$case_dir/stderr" >/dev/null
  [[ ! -e "$case_dir/harness_started" ]]
}

run_missing_case SWIFT_INFER_ENDPOINT
run_missing_case SWIFT_INFER_AGENT_TOKEN

DRIVER_FAILURE_STATE="$TEST_ROOT/driver-failure-state"
mkdir -p "$DRIVER_FAILURE_STATE"
set +e
SWIFT_INFER_ENDPOINT='https://swift.example' \
SWIFT_INFER_AGENT_TOKEN='fixture-secret-never-written' \
FAKE_DRIVER_FAIL=1 \
FAKE_STATE_DIR="$DRIVER_FAILURE_STATE" \
PANEL_SELFDRIVE_HARNESS="$FAKE_HARNESS" \
PANEL_SELFDRIVE_DRIVER_BIN="$FAKE_DRIVER" \
PANEL_SELFDRIVE_BD_BIN="$FAKE_BD" \
PANEL_SELFDRIVE_OUTPUT_ROOT="$DRIVER_FAILURE_STATE/output" \
  "$SCRIPT" macos >"$DRIVER_FAILURE_STATE/stdout" 2>"$DRIVER_FAILURE_STATE/stderr"
driver_failure_status=$?
set -e
[[ "$driver_failure_status" == 3 ]]
DRIVER_FAILURE_RUN_DIR="$(run_dir_from_stderr "$DRIVER_FAILURE_STATE/stderr")"
[[ -s "$DRIVER_FAILURE_RUN_DIR/panel_probe.json" ]]
[[ -s "$DRIVER_FAILURE_RUN_DIR/panel.log" ]]
[[ -s "$DRIVER_FAILURE_RUN_DIR/sample_app.log" ]]
grep -Fx 'PANEL_SELFDRIVE_RECEIPT=failed' "$DRIVER_FAILURE_STATE/bd_notes" >/dev/null
grep -E '^RUN_HEAD=[0-9a-f]{40}$' "$DRIVER_FAILURE_STATE/bd_notes" >/dev/null
grep -Fx 'FURTHEST_POINT=outer trajectory turn 5, proposed_action.tool=core.done' \
  "$DRIVER_FAILURE_STATE/bd_notes" >/dev/null
grep -Fx 'TURN_COUNT=6' "$DRIVER_FAILURE_STATE/bd_notes" >/dev/null
grep -Fx 'NON_EMPTY_NODE_TURN_COUNT=3' "$DRIVER_FAILURE_STATE/bd_notes" >/dev/null
grep -Fx 'LAST_PROPOSED_ACTION=core.done' "$DRIVER_FAILURE_STATE/bd_notes" >/dev/null
grep -Fx 'FOOTER_OUTCOME=absent' "$DRIVER_FAILURE_STATE/bd_notes" >/dev/null
grep -Fx 'PANEL_PROBE_OBSERVATION_KEYS=semantics' "$DRIVER_FAILURE_STATE/bd_notes" >/dev/null
grep -Fx 'PANEL_PROBE_TOP_LEVEL_KEYS=isolate_id,handshake,observation' \
  "$DRIVER_FAILURE_STATE/bd_notes" >/dev/null
grep -Fx 'PANEL_LOG_LAST_20_BEGIN' "$DRIVER_FAILURE_STATE/bd_notes" >/dev/null
grep -Fx 'panel fixture log' "$DRIVER_FAILURE_STATE/bd_notes" >/dev/null
grep -Fx 'PANEL_LOG_LAST_20_END' "$DRIVER_FAILURE_STATE/bd_notes" >/dev/null

READBACK_STATE="$TEST_ROOT/readback-state"
mkdir -p "$READBACK_STATE"
set +e
SWIFT_INFER_ENDPOINT='https://swift.example' \
SWIFT_INFER_AGENT_TOKEN='fixture-secret-never-written' \
FAKE_BD_DROP_APPEND=1 \
FAKE_STATE_DIR="$READBACK_STATE" \
PANEL_SELFDRIVE_HARNESS="$FAKE_HARNESS" \
PANEL_SELFDRIVE_DRIVER_BIN="$FAKE_DRIVER" \
PANEL_SELFDRIVE_BD_BIN="$FAKE_BD" \
PANEL_SELFDRIVE_OUTPUT_ROOT="$READBACK_STATE/output" \
  "$SCRIPT" macos >"$READBACK_STATE/stdout" 2>"$READBACK_STATE/stderr"
readback_status=$?
set -e
(( readback_status != 0 ))
grep -F 'bd read-back' "$READBACK_STATE/stderr" >/dev/null

LEAK_STATE="$TEST_ROOT/leak-state"
mkdir -p "$LEAK_STATE"
set +e
SWIFT_INFER_ENDPOINT='https://swift.example' \
SWIFT_INFER_AGENT_TOKEN='fixture-secret-never-written' \
FAKE_DRIVER_LEAK=1 \
FAKE_STATE_DIR="$LEAK_STATE" \
PANEL_SELFDRIVE_HARNESS="$FAKE_HARNESS" \
PANEL_SELFDRIVE_DRIVER_BIN="$FAKE_DRIVER" \
PANEL_SELFDRIVE_BD_BIN="$FAKE_BD" \
PANEL_SELFDRIVE_OUTPUT_ROOT="$LEAK_STATE/output" \
  "$SCRIPT" macos >"$LEAK_STATE/stdout" 2>"$LEAK_STATE/stderr"
leak_status=$?
set -e
(( leak_status != 0 ))
LEAK_RUN_DIR="$(run_dir_from_stderr "$LEAK_STATE/stderr")"
[[ -d "$LEAK_RUN_DIR" ]]
[[ -s "$LEAK_RUN_DIR/panel.log" ]]
[[ -s "$LEAK_RUN_DIR/panel_probe.json" ]]
grep -F '<REDACTED:SWIFT_INFER_AGENT_TOKEN>' "$LEAK_RUN_DIR/driver.log" >/dev/null
! grep -F 'fixture-secret-never-written' "$LEAK_RUN_DIR/driver.log"
grep -Fx 'CAPTURED_OUTPUT_SECRET_SCAN=leak-redacted' "$LEAK_STATE/bd_notes" >/dev/null
! grep -R -F 'fixture-secret-never-written' "$LEAK_STATE/output"
! grep -F 'fixture-secret-never-written' "$LEAK_STATE/bd_notes"
! grep -F 'fixture-secret-never-written' "$LEAK_STATE/stdout"
! grep -F 'fixture-secret-never-written' "$LEAK_STATE/stderr"

ENDPOINT_LEAK_STATE="$TEST_ROOT/endpoint-leak-state"
mkdir -p "$ENDPOINT_LEAK_STATE"
set +e
SWIFT_INFER_ENDPOINT='https://private-swift.example' \
SWIFT_INFER_AGENT_TOKEN='fixture-token' \
FAKE_PANEL_ENDPOINT_LEAK=1 \
FAKE_STATE_DIR="$ENDPOINT_LEAK_STATE" \
PANEL_SELFDRIVE_HARNESS="$FAKE_HARNESS" \
PANEL_SELFDRIVE_DRIVER_BIN="$FAKE_DRIVER" \
PANEL_SELFDRIVE_BD_BIN="$FAKE_BD" \
PANEL_SELFDRIVE_OUTPUT_ROOT="$ENDPOINT_LEAK_STATE/output" \
  "$SCRIPT" macos >"$ENDPOINT_LEAK_STATE/stdout" 2>"$ENDPOINT_LEAK_STATE/stderr"
endpoint_leak_status=$?
set -e
(( endpoint_leak_status == 0 ))
ENDPOINT_RUN_DIR="$(run_dir_from_stderr "$ENDPOINT_LEAK_STATE/stderr")"
[[ -d "$ENDPOINT_RUN_DIR" ]]
grep -F 'https://private-swift.example' "$ENDPOINT_RUN_DIR/panel.log" >/dev/null
grep -Fx 'CAPTURED_OUTPUT_SECRET_SCAN=clean' "$ENDPOINT_LEAK_STATE/stdout" >/dev/null
grep -Fx 'PANEL_SELFDRIVE_RECEIPT=passed' "$ENDPOINT_LEAK_STATE/bd_notes" >/dev/null

PINNED_STATE="$TEST_ROOT/pinned-state"
mkdir -p "$PINNED_STATE"
env -u PANEL_SELFDRIVE_MODEL_ID \
SWIFT_INFER_MODEL='qwen3.8-27b-8bit' \
SWIFT_INFER_ENDPOINT='https://swift.example' \
SWIFT_INFER_AGENT_TOKEN='fixture-secret-never-written' \
FAKE_STATE_DIR="$PINNED_STATE" \
PANEL_SELFDRIVE_HARNESS="$FAKE_HARNESS" \
PANEL_SELFDRIVE_DRIVER_BIN="$FAKE_DRIVER" \
PANEL_SELFDRIVE_BD_BIN="$FAKE_BD" \
PANEL_SELFDRIVE_OUTPUT_ROOT="$PINNED_STATE/output" \
  "$SCRIPT" macos >"$PINNED_STATE/stdout" 2>"$PINNED_STATE/stderr"
grep -Fx 'INNER_PANEL_MODEL_ID=qwen3.8-27b-8bit' \
  "$PINNED_STATE/bd_notes" >/dev/null
grep -Fx 'OUTER_DRIVER_MODEL_ID=qwen3.8-27b-8bit' \
  "$PINNED_STATE/bd_notes" >/dev/null

CONFLICT_STATE="$TEST_ROOT/conflict-state"
mkdir -p "$CONFLICT_STATE"
set +e
PANEL_SELFDRIVE_MODEL_ID='qwen3.8-27b-8bit' \
SWIFT_INFER_MODEL='qwen3.6-35b-a3b-8bit' \
SWIFT_INFER_ENDPOINT='https://swift.example' \
SWIFT_INFER_AGENT_TOKEN='fixture-secret-never-written' \
FAKE_STATE_DIR="$CONFLICT_STATE" \
PANEL_SELFDRIVE_HARNESS="$FAKE_HARNESS" \
PANEL_SELFDRIVE_DRIVER_BIN="$FAKE_DRIVER" \
PANEL_SELFDRIVE_BD_BIN="$FAKE_BD" \
PANEL_SELFDRIVE_OUTPUT_ROOT="$CONFLICT_STATE/output" \
  "$SCRIPT" macos >"$CONFLICT_STATE/stdout" 2>"$CONFLICT_STATE/stderr"
conflict_status=$?
set -e
[[ "$conflict_status" == 64 ]]
grep -F 'one name must pin both harnesses' "$CONFLICT_STATE/stderr" >/dev/null
[[ ! -e "$CONFLICT_STATE/harness_started" ]]

MISMATCH_STATE="$TEST_ROOT/mismatch-state"
mkdir -p "$MISMATCH_STATE"
set +e
env -u SWIFT_INFER_MODEL \
PANEL_SELFDRIVE_MODEL_ID='qwen3.8-27b-8bit' \
FAKE_RESOLVED_MODEL_ID='qwen3.6-35b-a3b-8bit' \
SWIFT_INFER_ENDPOINT='https://swift.example' \
SWIFT_INFER_AGENT_TOKEN='fixture-secret-never-written' \
FAKE_STATE_DIR="$MISMATCH_STATE" \
PANEL_SELFDRIVE_HARNESS="$FAKE_HARNESS" \
PANEL_SELFDRIVE_DRIVER_BIN="$FAKE_DRIVER" \
PANEL_SELFDRIVE_BD_BIN="$FAKE_BD" \
PANEL_SELFDRIVE_OUTPUT_ROOT="$MISMATCH_STATE/output" \
  "$SCRIPT" macos >"$MISMATCH_STATE/stdout" 2>"$MISMATCH_STATE/stderr"
mismatch_status=$?
set -e
[[ "$mismatch_status" != 0 ]]
grep -Fx 'PANEL_SELFDRIVE_RECEIPT=failed' "$MISMATCH_STATE/bd_notes" >/dev/null
grep -Fx 'INNER_PANEL_MODEL_ID=qwen3.6-35b-a3b-8bit' \
  "$MISMATCH_STATE/bd_notes" >/dev/null
grep -F 'but the run requested qwen3.8-27b-8bit' \
  "$MISMATCH_STATE/bd_notes" >/dev/null

printf '%s\n' 'run_panel_selfdrive_scenario_test: PASS'
