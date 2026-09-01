#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HARNESS="${PANEL_SELFDRIVE_HARNESS:-$ROOT/tool/run_panel_selfdrive.sh}"
DART_BIN="${PANEL_SELFDRIVE_DART_BIN:-dart}"
SCENARIO="$ROOT/packages/leonard_cli/scenarios/leonard_devtools_panel.md"
VERIFY="$ROOT/tool/verify_panel_selfdrive_receipt.dart"
DEVICE="${1:-macos}"
STARTUP_TIMEOUT_SECONDS="${PANEL_SELFDRIVE_STARTUP_TIMEOUT_SECONDS:-300}"

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
export PANEL_SELFDRIVE_MODEL_ID="${PANEL_SELFDRIVE_MODEL_ID:-qwen3.6-35b-a3b-8bit}"
[[ "$STARTUP_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]] || {
  printf '%s\n' 'run_panel_selfdrive_scenario: startup timeout must be a positive integer' >&2
  exit 64
}
[[ -x "$HARNESS" ]] || {
  printf 'run_panel_selfdrive_scenario: harness is not executable: %s\n' "$HARNESS" >&2
  exit 1
}
[[ -f "$SCENARIO" && -f "$VERIFY" ]] || {
  printf '%s\n' 'run_panel_selfdrive_scenario: scenario assets are missing' >&2
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
  "$TRAJECTORY" "$DRIVER_LOG" "$HARNESS_LOG" 2>"$VERIFY_LOG")"
verify_status=$?
set -e
if (( verify_status == 2 )); then
  rm -rf -- "$RUN_DIR"
  printf '%s\n' 'run_panel_selfdrive_scenario: secret scan failed; captured files removed' >&2
  exit 1
fi
if (( driver_status != 0 )); then
  sed -n '1,160p' "$DRIVER_LOG" >&2
  printf 'run_panel_selfdrive_scenario: outer driver exited %d\n' "$driver_status" >&2
  exit "$driver_status"
fi
if (( verify_status != 0 )); then
  sed -n '1,160p' "$VERIFY_LOG" >&2
  exit 1
fi
sed -n '1,160p' "$DRIVER_LOG" >&2
printf '%s\n' "$receipt"
