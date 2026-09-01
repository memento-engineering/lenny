#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/tool/run_panel_selfdrive.sh"
MODE="${1:-all}"
TEST_STARTUP_TIMEOUT_SECONDS="${SELFDRIVE_TEST_STARTUP_TIMEOUT_SECONDS:-15}"
case "$MODE" in
  all|happy|failures) ;;
  *) printf 'usage: %s [all|happy|failures]\n' "$0" >&2; exit 64 ;;
esac
[[ "$TEST_STARTUP_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]] || {
  printf '%s\n' 'run_panel_selfdrive_test: SELFDRIVE_TEST_STARTUP_TIMEOUT_SECONDS must be a positive integer' >&2
  exit 64
}

[[ -x "$SCRIPT" ]] || {
  printf 'run_panel_selfdrive_test: script is not executable: %s\n' "$SCRIPT" >&2
  exit 1
}
bash -n "$SCRIPT"

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/run-panel-selfdrive-test.XXXXXX")"
FAKE_BIN="$TEST_ROOT/bin"
mkdir -p "$FAKE_BIN"
cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

cat >"$FAKE_BIN/flutter" <<'FAKE_FLUTTER'
#!/usr/bin/env bash
set -euo pipefail

hold() {
  trap 'exit 0' INT TERM
  while :; do
    sleep 0.1
  done
}

case "$PWD" in
  */packages/leonard_flutter/example/sample_app)
    printf '%s\n' "$*" >"$FAKE_STATE_DIR/sample_args"
    if [[ "${FAKE_MISSING_VALUE:-none}" != sample_vm ]]; then
      printf '%s\n' \
        'A Dart VM Service on fake macOS is available at: http://127.0.0.1:5000/sample=/'
    fi
    if [[ "${FAKE_MISSING_VALUE:-none}" != dtd ]]; then
      printf '%s\n' \
        'The Dart Tooling Daemon is available at: ws://127.0.0.1:6000/dtd=/'
    fi
    if [[ "${FAKE_MISSING_VALUE:-none}" == sample_vm ||
          "${FAKE_MISSING_VALUE:-none}" == dtd ]]; then
      exit 94
    fi
    hold
    ;;
  */packages/leonard_devtools)
    printf '%s\n' "$*" >"$FAKE_STATE_DIR/panel_args"
    if [[ "${FAKE_MISSING_VALUE:-none}" == panel_url ]]; then
      exit 95
    fi
    : >"$FAKE_STATE_DIR/panel_served"
    printf '%s\n' \
      'dev/selfdrive_main.dart is being served at http://localhost:9101'
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
      [[ -f "$FAKE_STATE_DIR/chrome_opened" ]] && break
      sleep 0.05
    done
    [[ -f "$FAKE_STATE_DIR/chrome_opened" ]] || exit 92
    if [[ "${FAKE_MISSING_VALUE:-none}" == panel_dwds ]]; then
      exit 96
    fi
    printf '%s\n' \
      'Debug service listening on ws://127.0.0.1:7000/panel=/ws'
    ;;
  *)
    printf 'unexpected flutter working directory: %s\n' "$PWD" >&2
    exit 93
    ;;
esac
FAKE_FLUTTER

cat >"$FAKE_BIN/chrome" <<'FAKE_CHROME'
#!/usr/bin/env bash
set -euo pipefail
[[ -f "$FAKE_STATE_DIR/panel_served" ]] || {
  printf 'Chrome opened before panel was served\n' >&2
  exit 91
}
printf '%s\n' "${1:-}" >"$FAKE_STATE_DIR/chrome_url"
: >"$FAKE_STATE_DIR/chrome_opened"
FAKE_CHROME
chmod +x "$FAKE_BIN/flutter" "$FAKE_BIN/chrome"

run_case() {
  local case_name="$1"
  local missing_value="$2"
  local case_dir="$TEST_ROOT/$case_name"
  local status
  mkdir -p "$case_dir"
  set +e
  FAKE_STATE_DIR="$case_dir" \
  FAKE_MISSING_VALUE="$missing_value" \
  SELFDRIVE_FLUTTER_BIN="$FAKE_BIN/flutter" \
  SELFDRIVE_CHROME_BIN="$FAKE_BIN/chrome" \
  SELFDRIVE_STARTUP_TIMEOUT_SECONDS="$TEST_STARTUP_TIMEOUT_SECONDS" \
    "$SCRIPT" macos >"$case_dir/stdout" 2>"$case_dir/stderr"
  status=$?
  set -e
  printf '%s\n' "$status" >"$case_dir/status"
}

if [[ "$MODE" == all || "$MODE" == happy ]]; then
  run_case happy none
  [[ "$(<"$TEST_ROOT/happy/status")" == 0 ]]
  expected_vm='ws://127.0.0.1:5000/sample=/ws'
  expected_dtd='ws://127.0.0.1:6000/dtd=/'
  expected_dwds='ws://127.0.0.1:7000/panel=/ws'
  expected_url='http://localhost:9101/?uri=ws%3A%2F%2F127.0.0.1%3A5000%2Fsample%3D%2Fws&dtdUri=ws%3A%2F%2F127.0.0.1%3A6000%2Fdtd%3D%2F'
  grep -Fx -- "$expected_dwds" "$TEST_ROOT/happy/stdout" >/dev/null
  [[ "$(wc -l <"$TEST_ROOT/happy/stdout" | tr -d ' ')" == 1 ]]
  grep -Fx -- "SAMPLE_APP_VM_URI=$expected_vm" "$TEST_ROOT/happy/stderr" >/dev/null
  grep -Fx -- "DTD_URI=$expected_dtd" "$TEST_ROOT/happy/stderr" >/dev/null
  grep -Fx -- "PANEL_URL=$expected_url" "$TEST_ROOT/happy/stderr" >/dev/null
  grep -Fx -- "PANEL_DWDS_URI=$expected_dwds" "$TEST_ROOT/happy/stderr" >/dev/null
  grep -Fx -- "$expected_url" "$TEST_ROOT/happy/chrome_url" >/dev/null
  grep -F -- 'run -d macos --print-dtd' "$TEST_ROOT/happy/sample_args" >/dev/null
  grep -F -- \
    'run -d web-server --web-port 9101 -t dev/selfdrive_main.dart --dart-define=use_simulated_environment=true' \
    "$TEST_ROOT/happy/panel_args" >/dev/null
  printf 'run_panel_selfdrive_test: happy PASS\n'
fi

if [[ "$MODE" == all || "$MODE" == failures ]]; then
  while IFS=: read -r missing_value value_name; do
    run_case "$missing_value" "$missing_value"
    [[ "$(<"$TEST_ROOT/$missing_value/status")" != 0 ]]
    grep -F -- \
      "run_panel_selfdrive: could not resolve $value_name" \
      "$TEST_ROOT/$missing_value/stderr" >/dev/null
  done <<'FAILURE_CASES'
sample_vm:SAMPLE_APP_VM_URI
dtd:DTD_URI
panel_url:PANEL_URL
panel_dwds:PANEL_DWDS_URI
FAILURE_CASES
  printf 'run_panel_selfdrive_test: failures PASS\n'
fi
