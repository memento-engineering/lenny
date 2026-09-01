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
cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

cat >"$FAKE_HARNESS" <<'FAKE_HARNESS'
#!/usr/bin/env bash
set -euo pipefail
: >"$FAKE_STATE_DIR/harness_started"
printf '%s\n' 'ws://127.0.0.1:7000/panel=/ws'
trap 'exit 0' INT TERM
while :; do
  sleep 0.1
done
FAKE_HARNESS

cat >"$FAKE_DRIVER" <<'FAKE_DRIVER'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$FAKE_STATE_DIR/driver_args"
output=''
goal_file=''
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
    *) shift ;;
  esac
done
[[ -n "$output" && -n "$goal_file" ]]
cp -f "$goal_file" "$FAKE_STATE_DIR/goal_file_content"
cat >"$output" <<'JSONL'
{"type":"turn","index":0,"observation":{"core":{"nodes":[]}},"proposed_action":{"tool":"core.enter_text","args":{"text":"${SWIFT_INFER_ENDPOINT}"}}}
{"type":"turn","index":1,"observation":{"core":{"nodes":[]}},"proposed_action":{"tool":"core.enter_text","args":{"text":"${SWIFT_INFER_AGENT_TOKEN}"}}}
{"type":"turn","index":2,"observation":{"core":{"nodes":[]}},"proposed_action":{"tool":"core.enter_text","args":{"text":"${PANEL_SELFDRIVE_MODEL_ID}"}}}
{"type":"turn","index":3,"observation":{"core":{"nodes":[{"label":"OK (2 models)"}]}},"proposed_action":{"tool":"core.tap","args":{}}}
{"type":"turn","index":4,"observation":{"core":{"nodes":[{"label":"#0 core.done()"},{"label":"Proposed action"},{"value":"core.done()"}]}},"proposed_action":{"tool":"core.tap","args":{}}}
{"type":"turn","index":5,"observation":{"core":{"nodes":[{"label":"Start","actions":["tap"],"state":[]}]}},"proposed_action":{"tool":"core.done","args":{"reason":"panel smoke passed: inner turn 0 tool core.done"}}}
JSONL
if [[ "${FAKE_DRIVER_LEAK:-0}" == 1 ]]; then
  printf '%s\n' "$SWIFT_INFER_AGENT_TOKEN" >&2
fi
FAKE_DRIVER
chmod +x "$FAKE_HARNESS" "$FAKE_DRIVER"

HAPPY_STATE="$TEST_ROOT/happy-state"
mkdir -p "$HAPPY_STATE"
SWIFT_INFER_ENDPOINT='https://swift.example' \
SWIFT_INFER_AGENT_TOKEN='fixture-secret-never-written' \
FAKE_STATE_DIR="$HAPPY_STATE" \
PANEL_SELFDRIVE_HARNESS="$FAKE_HARNESS" \
PANEL_SELFDRIVE_DRIVER_BIN="$FAKE_DRIVER" \
PANEL_SELFDRIVE_OUTPUT_ROOT="$TEST_ROOT/output" \
  "$SCRIPT" macos >"$TEST_ROOT/happy.stdout" 2>"$TEST_ROOT/happy.stderr"
grep -F 'TRAJECTORY_PATH=' "$TEST_ROOT/happy.stdout" >/dev/null
grep -Fx 'OBSERVED_TURN_INDEX=0' "$TEST_ROOT/happy.stdout" >/dev/null
grep -Fx 'OBSERVED_TURN_TOOL=core.done' "$TEST_ROOT/happy.stdout" >/dev/null
grep -Fx 'PROMPT_FORM=enabled' "$TEST_ROOT/happy.stdout" >/dev/null
grep -Fx 'CAPTURED_OUTPUT_SECRET_SCAN=clean' "$TEST_ROOT/happy.stdout" >/dev/null
grep -Fx -- '--goal-file' "$HAPPY_STATE/driver_args" >/dev/null
grep -Fx -- '--action-env' "$HAPPY_STATE/driver_args" >/dev/null
grep -F 'SWIFT_INFER_AGENT_TOKEN' "$HAPPY_STATE/goal_file_content" >/dev/null
! grep -R -F 'fixture-secret-never-written' "$TEST_ROOT/output"

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
      PANEL_SELFDRIVE_OUTPUT_ROOT="$case_dir/output" \
      "$SCRIPT" macos >"$case_dir/stdout" 2>"$case_dir/stderr"
  else
    env -u SWIFT_INFER_AGENT_TOKEN \
      SWIFT_INFER_ENDPOINT='https://swift.example' \
      FAKE_STATE_DIR="$case_dir" \
      PANEL_SELFDRIVE_HARNESS="$FAKE_HARNESS" \
      PANEL_SELFDRIVE_DRIVER_BIN="$FAKE_DRIVER" \
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

LEAK_STATE="$TEST_ROOT/leak-state"
mkdir -p "$LEAK_STATE"
set +e
SWIFT_INFER_ENDPOINT='https://swift.example' \
SWIFT_INFER_AGENT_TOKEN='fixture-secret-never-written' \
FAKE_DRIVER_LEAK=1 \
FAKE_STATE_DIR="$LEAK_STATE" \
PANEL_SELFDRIVE_HARNESS="$FAKE_HARNESS" \
PANEL_SELFDRIVE_DRIVER_BIN="$FAKE_DRIVER" \
PANEL_SELFDRIVE_OUTPUT_ROOT="$LEAK_STATE/output" \
  "$SCRIPT" macos >"$LEAK_STATE/stdout" 2>"$LEAK_STATE/stderr"
leak_status=$?
set -e
(( leak_status != 0 ))
[[ -d "$LEAK_STATE/output" ]]
[[ -z "$(find "$LEAK_STATE/output" -mindepth 1 -maxdepth 1 -print -quit)" ]]
! grep -F 'fixture-secret-never-written' "$LEAK_STATE/stdout"
! grep -F 'fixture-secret-never-written' "$LEAK_STATE/stderr"

printf '%s\n' 'run_panel_selfdrive_scenario_test: PASS'
