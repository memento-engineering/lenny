#!/usr/bin/env bash
set -euo pipefail

# The sanctioned path for a panel self-drive receipt is the station's
# `selfdrive` circuit in grid_assets/leonard_grid_assets. A bead carrying
# selfdrive.scenario / selfdrive.outer_model / selfdrive.inner_model mounts
# preflight -> panel-harness (daemon) -> outer-driver -> verify, and the station
# writes the receipt from step outcomes. This wrapper remains the operator's
# manual fallback; the circuit reuses its harness and verifier commands.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HARNESS="${PANEL_SELFDRIVE_HARNESS:-$ROOT/tool/run_panel_selfdrive.sh}"
DART_BIN="${PANEL_SELFDRIVE_DART_BIN:-dart}"
SCENARIO="$ROOT/packages/leonard_cli/scenarios/leonard_devtools_panel.md"
VERIFY="$ROOT/tool/verify_panel_selfdrive_receipt.dart"
DEVICE="${1:-macos}"
STARTUP_TIMEOUT_SECONDS="${PANEL_SELFDRIVE_STARTUP_TIMEOUT_SECONDS:-300}"
CORE_BUDGET_BYTES="${PANEL_SELFDRIVE_CORE_BUDGET_BYTES:-131072}"
BD_BIN="${PANEL_SELFDRIVE_BD_BIN:-bd}"
BEAD_ID="${PANEL_SELFDRIVE_BEAD_ID:-lenny-f7nx.6}"
ROUND_MARKER='PANEL_SELFDRIVE_ROUND=10'
RUN_HEAD="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')"
RUN_HEAD_COMMITTED_AT="$(git -C "$ROOT" show -s --format=%cI HEAD 2>/dev/null ||
  printf 'unknown')"

if (( $# > 1 )); then
  printf 'usage: %s [sample-app-device-id]\n' "$0" >&2
  exit 64
fi
for name in SWIFT_INFER_ENDPOINT SWIFT_INFER_AGENT_TOKEN; do
  if [[ -z "${!name:-}" ]]; then
    printf 'run_panel_selfdrive_scenario: missing %s\n' "$name" >&2
    exit 64
  fi
done
# ONE name pins BOTH harnesses. SWIFT_INFER_MODEL is what leonard_cli's
# buildProvider reads for the OUTER driver and what run_panel_selfdrive.sh
# --dart-defines into the INNER panel build; PANEL_SELFDRIVE_MODEL_ID is the
# scenario's own name for the same value. Two different ids on one swift-infer
# server make each harness's load evict the other's node (LRU), so a
# disagreement is refused LOUDLY rather than reconciled silently.
if [[ -n "${PANEL_SELFDRIVE_MODEL_ID:-}" && -n "${SWIFT_INFER_MODEL:-}" &&
      "$PANEL_SELFDRIVE_MODEL_ID" != "$SWIFT_INFER_MODEL" ]]; then
  printf 'run_panel_selfdrive_scenario: PANEL_SELFDRIVE_MODEL_ID=%s disagrees with SWIFT_INFER_MODEL=%s; one name must pin both harnesses\n' \
    "$PANEL_SELFDRIVE_MODEL_ID" "$SWIFT_INFER_MODEL" >&2
  exit 64
fi
PANEL_SELFDRIVE_MODEL_ID="${PANEL_SELFDRIVE_MODEL_ID:-${SWIFT_INFER_MODEL:-}}"
if [[ -z "$PANEL_SELFDRIVE_MODEL_ID" ]]; then
  printf '%s\n' 'run_panel_selfdrive_scenario: set SWIFT_INFER_MODEL (or PANEL_SELFDRIVE_MODEL_ID); one name pins both harnesses and there is no safe default' >&2
  exit 64
fi
export PANEL_SELFDRIVE_MODEL_ID
export SWIFT_INFER_MODEL="$PANEL_SELFDRIVE_MODEL_ID"
[[ "$STARTUP_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]] || {
  printf '%s\n' 'run_panel_selfdrive_scenario: startup timeout must be a positive integer' >&2
  exit 64
}
[[ "$CORE_BUDGET_BYTES" =~ ^[1-9][0-9]*$ ]] || {
  printf '%s\n' 'run_panel_selfdrive_scenario: core budget must be positive' >&2
  exit 64
}
command -v "$BD_BIN" >/dev/null 2>&1 || {
  printf 'run_panel_selfdrive_scenario: bd executable not found: %s\n' \
    "$BD_BIN" >&2
  exit 1
}
[[ -x "$HARNESS" ]] || {
  printf 'run_panel_selfdrive_scenario: harness is not executable: %s\n' "$HARNESS" >&2
  exit 1
}
[[ -f "$SCENARIO" && -f "$VERIFY" ]] || {
  printf '%s\n' 'run_panel_selfdrive_scenario: scenario assets are missing' >&2
  exit 1
}
DONE_REASON_PATTERN="$(sed -n 's/^done-reason-pattern: //p' "$SCENARIO" |
  head -n 1)"
[[ -n "$DONE_REASON_PATTERN" ]] || {
  printf '%s\n' \
    'run_panel_selfdrive_scenario: scenario declares no done-reason-pattern' >&2
  exit 1
}
DONE_EVIDENCE_PATTERN="$(sed -n 's/^done-evidence-pattern: //p' "$SCENARIO" |
  head -n 1)"
[[ -n "$DONE_EVIDENCE_PATTERN" ]] || {
  printf '%s\n' \
    'run_panel_selfdrive_scenario: scenario declares no done-evidence-pattern' >&2
  exit 1
}

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUTPUT_ROOT="${PANEL_SELFDRIVE_OUTPUT_ROOT:-$ROOT/packages/leonard_cli/trajectories}"
RUN_DIR="$OUTPUT_ROOT/panel-selfdrive-$STAMP-$$"
mkdir -p "$RUN_DIR"
chmod 700 "$RUN_DIR"
TRAJECTORY="$RUN_DIR/outer.jsonl"
DRIVER_LOG="$RUN_DIR/driver.log"
HARNESS_LOG="$RUN_DIR/harness.log"
HARNESS_OUT="$RUN_DIR/panel_dwds.out"
VERIFY_LOG="$RUN_DIR/verify.log"
PANEL_PROBE="$RUN_DIR/panel_probe.json"
PANEL_LOG="$RUN_DIR/panel.log"
SAMPLE_LOG="$RUN_DIR/sample_app.log"
printf 'PANEL_SELFDRIVE_RUN_DIR=%s\n' "$RUN_DIR" >&2
HARNESS_PID=''

cleanup() {
  local status=$?
  trap - EXIT
  if [[ -n "$HARNESS_PID" ]] && kill -0 "$HARNESS_PID" 2>/dev/null; then
    kill "$HARNESS_PID" 2>/dev/null || true
    wait "$HARNESS_PID" 2>/dev/null || true
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

PANEL_SELFDRIVE_ARTIFACT_DIR="$RUN_DIR" \
  "$HARNESS" "$DEVICE" >"$HARNESS_OUT" 2>"$HARNESS_LOG" &
HARNESS_PID=$!
deadline=$((SECONDS + STARTUP_TIMEOUT_SECONDS))
PANEL_DWDS_URI=''
while (( SECONDS < deadline )); do
  PANEL_DWDS_URI="$(sed -n '1p' "$HARNESS_OUT" 2>/dev/null || true)"
  [[ "$PANEL_DWDS_URI" == ws://* || "$PANEL_DWDS_URI" == wss://* ]] && break
  kill -0 "$HARNESS_PID" 2>/dev/null || {
    printf '%s\n' 'run_panel_selfdrive_scenario: harness exited before panel DWDS readiness' >&2
    exit 1
  }
  sleep 1
done
[[ "$PANEL_DWDS_URI" == ws://* || "$PANEL_DWDS_URI" == wss://* ]] || {
  printf '%s\n' 'run_panel_selfdrive_scenario: panel DWDS readiness timed out' >&2
  exit 1
}

DRIVER_ARGS=(
  --vm-uri "$PANEL_DWDS_URI"
  --goal-file "$SCENARIO"
  --model qwen-mlx
  --output "$TRAJECTORY"
  --turn-budget 180
  --done-reason-pattern "$DONE_REASON_PATTERN"
  --done-evidence-pattern "$DONE_EVIDENCE_PATTERN"
  --core-budget-bytes "$CORE_BUDGET_BYTES"
  --probe-artifact "$PANEL_PROBE"
  --action-env SWIFT_INFER_ENDPOINT
  --action-env SWIFT_INFER_AGENT_TOKEN
  --action-env PANEL_SELFDRIVE_MODEL_ID
)
set +e
if [[ -n "${PANEL_SELFDRIVE_DRIVER_BIN:-}" ]]; then
  "$PANEL_SELFDRIVE_DRIVER_BIN" "${DRIVER_ARGS[@]}" >"$DRIVER_LOG" 2>&1
else
  "$DART_BIN" run "$ROOT/packages/leonard_cli/bin/leonard_cli.dart" \
    "${DRIVER_ARGS[@]}" >"$DRIVER_LOG" 2>&1
fi
driver_status=$?
set -e

set +e
receipt="$("$DART_BIN" run "$VERIFY" \
  "$TRAJECTORY" \
  "$DRIVER_LOG" \
  "$HARNESS_LOG" \
  "$PANEL_PROBE" \
  "$PANEL_LOG" \
  "$SAMPLE_LOG" \
  2>"$VERIFY_LOG")"
verify_status=$?
set -e
# The note's inner model id comes from the verifier's OBSERVED value. The env
# only records what was REQUESTED; copying it is what made the round-9 receipt
# claim a model the panel never ran.
inner_model_resolved="$(printf '%s\n' "$receipt" |
  sed -n 's/^INNER_PANEL_MODEL_RESOLVED=//p' | head -n 1)"
printf '%s\n' "$driver_status" >"$RUN_DIR/driver.status"
printf '%s\n' "$verify_status" >"$RUN_DIR/verify.status"

scrub_guard() {
  local text="$1"
  if [[ -n "$text" ]] &&
     { [[ "$text" == *"$SWIFT_INFER_ENDPOINT"* ]] ||
       [[ "$text" == *"$SWIFT_INFER_AGENT_TOKEN"* ]]; }; then
    printf '%s\n' 'redacted-contained-credential'
    return
  fi
  printf '%s\n' "$text"
}

furthest_point() {
  local last_turn_line last_index last_tool
  last_turn_line="$(grep -F '"type":"turn"' "$TRAJECTORY" | tail -n 1 || true)"
  last_index="$(printf '%s' "$last_turn_line" |
    sed -n 's/^{"type":"turn","index":\([0-9]*\).*/\1/p')"
  last_tool="$(printf '%s' "${last_turn_line#*\"proposed_action\":}" |
    sed -n 's/^[^}]*"tool":"\([^"]*\)".*/\1/p')"
  printf 'outer trajectory turn %s, proposed_action.tool=%s\n' \
    "${last_index:-unknown}" "${last_tool:-unknown}"
}

persist_receipt() {
  local note="$1"
  printf '%s\n' "$note" >"$RUN_DIR/bead.note"
  "$BD_BIN" update "$BEAD_ID" --actor build --append-notes "$note" >/dev/null
  "$BD_BIN" show "$BEAD_ID" >"$RUN_DIR/bead.readback"
  grep -Fq "$ROUND_MARKER" "$RUN_DIR/bead.readback" || {
    printf '%s\n' \
      "run_panel_selfdrive_scenario: $ROUND_MARKER missing after bd read-back" \
      >&2
    return 1
  }
}

probe_key_list() {
  local keys='' key
  if [[ -s "$PANEL_PROBE" ]]; then
    for key in isolate_id handshake observation; do
      grep -Fq "\"$key\":" "$PANEL_PROBE" && keys+="${keys:+,}$key"
    done
  fi
  printf '%s\n' "${keys:-absent}"
}

if (( verify_status == 2 )); then
  leak_name="$(sed -n 's/.*: \([A-Z_]*\) value found$/\1/p' \
    "$VERIFY_LOG" | head -n 1 || true)"
  note="$(printf '%s\n' \
    "$ROUND_MARKER" \
    'RECEIPT_PATH=manual-fallback' \
    "RUN_HEAD=$RUN_HEAD" \
    "RUN_HEAD_COMMITTED_AT=$RUN_HEAD_COMMITTED_AT" \
    "RUN_STARTED_AT=$STAMP" \
    'PANEL_SELFDRIVE_RECEIPT=failed' \
    "SCENARIO_EXIT_STATUS=$driver_status" \
    "VERIFIER_EXIT_STATUS=$verify_status" \
    'FURTHEST_POINT=secret scan' \
    'FAILING_ASSERTION=no credential value appears in captured output' \
    "RAW_ERROR=secret scan redacted ${leak_name:-unknown}" \
    "$(scrub_guard "$receipt")" \
    "INNER_PANEL_MODEL_ID=${inner_model_resolved:-absent}" \
    "OUTER_DRIVER_MODEL_ID=$SWIFT_INFER_MODEL" \
    "PANEL_PROBE_TOP_LEVEL_KEYS=$(probe_key_list)")"
  persist_receipt "$note"
  printf '%s\n' \
    'run_panel_selfdrive_scenario: credential redacted in captured output; evidence retained' >&2
  printf '%s\n' "$note" >&2
  exit 1
fi

if (( driver_status != 0 || verify_status != 0 )); then
  if (( driver_status != 0 )); then
    raw_error_source="$DRIVER_LOG"
    failing='./tool/run_panel_selfdrive_scenario.sh exits zero (outer driver)'
  else
    raw_error_source="$VERIFY_LOG"
    failing='verifier accepts the trajectory receipt'
  fi
  raw_error="$(scrub_guard "$(grep -v '^[[:space:]]*$' "$raw_error_source" |
    tail -n 1 || true)")"
  note="$(printf '%s\n' \
    "$ROUND_MARKER" \
    'RECEIPT_PATH=manual-fallback' \
    "RUN_HEAD=$RUN_HEAD" \
    "RUN_HEAD_COMMITTED_AT=$RUN_HEAD_COMMITTED_AT" \
    "RUN_STARTED_AT=$STAMP" \
    'PANEL_SELFDRIVE_RECEIPT=failed' \
    "SCENARIO_EXIT_STATUS=$driver_status" \
    "VERIFIER_EXIT_STATUS=$verify_status" \
    "FURTHEST_POINT=$(furthest_point)" \
    "FAILING_ASSERTION=$failing" \
    "RAW_ERROR=${raw_error:-none-captured}" \
    "$(scrub_guard "$receipt")" \
    "INNER_PANEL_MODEL_ID=${inner_model_resolved:-absent}" \
    "OUTER_DRIVER_MODEL_ID=$SWIFT_INFER_MODEL" \
    "PANEL_PROBE_TOP_LEVEL_KEYS=$(probe_key_list)" \
    'PANEL_LOG_LAST_20_BEGIN' \
    "$(scrub_guard "$(tail -n 20 "$PANEL_LOG" 2>/dev/null || true)")" \
    'PANEL_LOG_LAST_20_END')"
  persist_receipt "$note"
  printf '%s\n' "$note" >&2
  sed -n '1,160p' "$raw_error_source" >&2
  (( driver_status != 0 )) && exit "$driver_status"
  exit 1
fi

note="$(printf '%s\n' \
  "$ROUND_MARKER" \
  'RECEIPT_PATH=manual-fallback' \
  "RUN_HEAD=$RUN_HEAD" \
  "RUN_HEAD_COMMITTED_AT=$RUN_HEAD_COMMITTED_AT" \
  "RUN_STARTED_AT=$STAMP" \
  'PANEL_SELFDRIVE_RECEIPT=passed' \
  'SCENARIO_EXIT_STATUS=0' \
  'VERIFIER_EXIT_STATUS=0' \
  'FAILING_ASSERTION=none' \
  "FURTHEST_POINT=$(furthest_point)" \
  "$receipt" \
  "INNER_PANEL_MODEL_ID=${inner_model_resolved:-absent}" \
  "OUTER_DRIVER_MODEL_ID=$SWIFT_INFER_MODEL" \
  "PANEL_PROBE_TOP_LEVEL_KEYS=$(probe_key_list)")"
persist_receipt "$note"
sed -n '1,160p' "$DRIVER_LOG" >&2
printf '%s\n' "$note"
