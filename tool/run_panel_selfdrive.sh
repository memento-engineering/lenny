#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAMPLE_APP="$ROOT/packages/leonard_flutter/example/sample_app"
PANEL="$ROOT/packages/leonard_devtools"
PANEL_PORT=9101
STARTUP_TIMEOUT_SECONDS="${SELFDRIVE_STARTUP_TIMEOUT_SECONDS:-300}"
FLUTTER_BIN="${SELFDRIVE_FLUTTER_BIN:-flutter}"
SAMPLE_DEVICE="${1:-macos}"
# ONE name pins BOTH harnesses. PANEL_SELFDRIVE_MODEL_ID is the scenario's own
# name for it; SWIFT_INFER_MODEL is what leonard_cli's buildProvider reads for
# the OUTER driver. The panel is a web build, so it takes the value at BUILD
# time through --dart-define.
PANEL_MODEL_ID="${PANEL_SELFDRIVE_MODEL_ID:-${SWIFT_INFER_MODEL:-qwen3.6-35b-a3b-8bit}}"

fail() {
  printf 'run_panel_selfdrive: %s\n' "$*" >&2
  exit 1
}

if (( $# > 1 )); then
  printf 'usage: %s [sample-app-device-id]\n' "$0" >&2
  exit 64
fi
[[ "$STARTUP_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]] ||
  fail 'SELFDRIVE_STARTUP_TIMEOUT_SECONDS must be a positive integer'
[[ -d "$SAMPLE_APP" ]] || fail "sample_app directory missing: $SAMPLE_APP"
[[ -f "$SAMPLE_APP/pubspec.yaml" ]] ||
  fail "sample_app pubspec missing: $SAMPLE_APP/pubspec.yaml"
[[ -d "$PANEL" ]] || fail "panel directory missing: $PANEL"
[[ -f "$PANEL/dev/selfdrive_main.dart" ]] ||
  fail "panel self-drive entrypoint missing: $PANEL/dev/selfdrive_main.dart"
command -v "$FLUTTER_BIN" >/dev/null 2>&1 ||
  fail "Flutter executable not found: $FLUTTER_BIN"

RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lenny-panel-selfdrive.XXXXXX")" ||
  fail 'could not create temporary run directory'
ARTIFACT_DIR="${PANEL_SELFDRIVE_ARTIFACT_DIR:-$RUN_DIR}"
[[ -d "$ARTIFACT_DIR" ]] ||
  fail "artifact directory missing: $ARTIFACT_DIR"
SAMPLE_LOG="$ARTIFACT_DIR/sample_app.log"
PANEL_LOG="$ARTIFACT_DIR/panel.log"
SAMPLE_APP_PID=''
PANEL_PID=''

cleanup() {
  local status=$?
  trap - EXIT
  local pid
  for pid in "$PANEL_PID" "$SAMPLE_APP_PID"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done
  for pid in "$PANEL_PID" "$SAMPLE_APP_PID"; do
    if [[ -n "$pid" ]]; then
      wait "$pid" 2>/dev/null || true
    fi
  done
  rm -rf -- "$RUN_DIR"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

print_log_tail() {
  local name="$1"
  local log="$2"
  if [[ -s "$log" ]]; then
    printf '%s\n' "run_panel_selfdrive: tail of $name log:" >&2
    tail -n 40 "$log" >&2 || true
  fi
}

wait_for_line() {
  local name="$1"
  local pid="$2"
  local log="$3"
  local pattern="$4"
  local deadline=$((SECONDS + STARTUP_TIMEOUT_SECONDS))
  local line=''

  while (( SECONDS < deadline )); do
    line="$(grep -E -- "$pattern" "$log" | tail -n 1 || true)"
    if [[ -n "$line" ]]; then
      printf '%s\n' "$line"
      return 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      print_log_tail "$name" "$log"
      fail "could not resolve $name: process exited before emitting its readiness line"
    fi
    sleep 1
  done

  print_log_tail "$name" "$log"
  fail "could not resolve $name within ${STARTUP_TIMEOUT_SECONDS}s"
}

normalize_vm_service_uri() {
  local http_uri="$1"
  local ws_uri
  case "$http_uri" in
    http://*) ws_uri="ws://${http_uri#http://}" ;;
    https://*) ws_uri="wss://${http_uri#https://}" ;;
    *) fail "could not resolve SAMPLE_APP_VM_URI: unsupported URI $http_uri" ;;
  esac
  ws_uri="${ws_uri%/}"
  case "$ws_uri" in
    */ws) ;;
    *) ws_uri="$ws_uri/ws" ;;
  esac
  printf '%s\n' "$ws_uri"
}

percent_encode() {
  local value="$1"
  local encoded=''
  local char
  local byte
  local i
  LC_ALL=C
  for ((i = 0; i < ${#value}; i++)); do
    char="${value:i:1}"
    case "$char" in
      [a-zA-Z0-9._~-]) encoded+="$char" ;;
      *)
        printf -v byte '%%%02X' "'$char"
        encoded+="$byte"
        ;;
    esac
  done
  printf '%s\n' "$encoded"
}

open_chrome() {
  local url="$1"
  if [[ -n "${SELFDRIVE_CHROME_BIN:-}" ]]; then
    [[ -x "$SELFDRIVE_CHROME_BIN" ]] ||
      fail "Chrome launcher is not executable: $SELFDRIVE_CHROME_BIN"
    "$SELFDRIVE_CHROME_BIN" "$url" ||
      fail 'Chrome launcher failed to open PANEL_URL'
    return
  fi

  case "$(uname -s)" in
    Darwin)
      command -v open >/dev/null 2>&1 || fail 'macOS open command not found'
      open -a 'Google Chrome' "$url" ||
        fail 'Google Chrome failed to open PANEL_URL'
      ;;
    Linux)
      local candidate
      local chrome_bin=''
      for candidate in google-chrome google-chrome-stable chromium chromium-browser; do
        if command -v "$candidate" >/dev/null 2>&1; then
          chrome_bin="$candidate"
          break
        fi
      done
      [[ -n "$chrome_bin" ]] || fail 'Google Chrome or Chromium executable not found'
      "$chrome_bin" "$url" || fail 'Chrome failed to open PANEL_URL'
      ;;
    *) fail "unsupported platform for Chrome launch: $(uname -s)" ;;
  esac
}

(
  cd "$SAMPLE_APP"
  exec "$FLUTTER_BIN" run -d "$SAMPLE_DEVICE" --print-dtd
) >"$SAMPLE_LOG" 2>&1 &
SAMPLE_APP_PID=$!

sample_vm_line="$(wait_for_line \
  SAMPLE_APP_VM_URI \
  "$SAMPLE_APP_PID" \
  "$SAMPLE_LOG" \
  'Dart VM Service on .* is available at: https?://[^[:space:]]+')"
sample_vm_http_uri="${sample_vm_line##* is available at: }"
sample_vm_http_uri="${sample_vm_http_uri%$'\r'}"
SAMPLE_APP_VM_URI="$(normalize_vm_service_uri "$sample_vm_http_uri")"

dtd_line="$(wait_for_line \
  DTD_URI \
  "$SAMPLE_APP_PID" \
  "$SAMPLE_LOG" \
  'The Dart Tooling Daemon is available at: (ws|wss)://[^[:space:]]+')"
DTD_URI="${dtd_line##* is available at: }"
DTD_URI="${DTD_URI%$'\r'}"
case "$DTD_URI" in
  ws://*|wss://*) ;;
  *) fail "could not resolve DTD_URI: unsupported URI $DTD_URI" ;;
esac

(
  cd "$PANEL"
  exec "$FLUTTER_BIN" run \
    -d web-server \
    --web-port "$PANEL_PORT" \
    -t dev/selfdrive_main.dart \
    --dart-define=use_simulated_environment=true \
    --dart-define=SWIFT_INFER_MODEL="$PANEL_MODEL_ID"
) >"$PANEL_LOG" 2>&1 &
PANEL_PID=$!

panel_line="$(wait_for_line \
  PANEL_URL \
  "$PANEL_PID" \
  "$PANEL_LOG" \
  "is being served at http://localhost:${PANEL_PORT}/?([[:space:]]|$)")"
panel_origin="${panel_line##* is being served at }"
panel_origin="${panel_origin%$'\r'}"
panel_origin="${panel_origin%/}"
expected_panel_origin="http://localhost:$PANEL_PORT"
[[ "$panel_origin" == "$expected_panel_origin" ]] ||
  fail "could not resolve PANEL_URL: expected $expected_panel_origin, got $panel_origin"

encoded_vm_uri="$(percent_encode "$SAMPLE_APP_VM_URI")"
encoded_dtd_uri="$(percent_encode "$DTD_URI")"
PANEL_URL="$panel_origin/?uri=$encoded_vm_uri&dtdUri=$encoded_dtd_uri"
open_chrome "$PANEL_URL"

panel_dwds_line="$(wait_for_line \
  PANEL_DWDS_URI \
  "$PANEL_PID" \
  "$PANEL_LOG" \
  'Debug service listening on (ws|wss)://[^[:space:]]+')"
PANEL_DWDS_URI="${panel_dwds_line##*Debug service listening on }"
PANEL_DWDS_URI="${PANEL_DWDS_URI%$'\r'}"
case "$PANEL_DWDS_URI" in
  ws://*|wss://*) ;;
  *) fail "could not resolve PANEL_DWDS_URI: unsupported URI $PANEL_DWDS_URI" ;;
esac

printf 'SAMPLE_APP_VM_URI=%s\n' "$SAMPLE_APP_VM_URI" >&2
printf 'DTD_URI=%s\n' "$DTD_URI" >&2
printf 'PANEL_URL=%s\n' "$PANEL_URL" >&2
printf 'PANEL_DWDS_URI=%s\n' "$PANEL_DWDS_URI" >&2
printf '%s\n' "$PANEL_DWDS_URI"

set +e
wait "$PANEL_PID"
panel_status=$?
set -e
PANEL_PID=''
if (( panel_status != 0 )); then
  print_log_tail panel "$PANEL_LOG"
  fail "panel process exited with status $panel_status"
fi
