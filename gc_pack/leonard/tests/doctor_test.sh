#!/usr/bin/env bash
set -euo pipefail

# Tests the doctor/ checks against a fake gc (for `gc config show --json`),
# fake leonard_cli builds and fake platform tools. The fakes reach a check
# only the way real tools reach the drive: gc through the check's PATH, the
# rest through PATH in a rig's env file. Runs the checks with /bin/bash so
# macOS's bash 3.2 is covered.

PACK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CHECKS="env-file leonard-cli platform-tools devices"
bash -n "$PACK/doctor/lib.sh"
for check in $CHECKS; do
  [ -x "$PACK/doctor/$check/run.sh" ] || {
    printf 'doctor_test: not executable: doctor/%s/run.sh\n' "$check" >&2
    exit 1
  }
  bash -n "$PACK/doctor/$check/run.sh"
  [ -f "$PACK/doctor/$check/doctor.toml" ] || {
    printf 'doctor_test: missing doctor/%s/doctor.toml\n' "$check" >&2
    exit 1
  }
done

TEST_ROOT="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/leonard-doctor-test.XXXXXX")" && pwd -P)"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
GC_BIN_DIR="$TEST_ROOT/gc-bin"   # on the check's PATH, as gc is in Gas City
TOOLS="$TEST_ROOT/tools"         # reachable only through an env file's PATH
OLD_CLI_DIR="$TEST_ROOT/old-cli"
BROKEN_CLI_DIR="$TEST_ROOT/broken-cli"
BROKEN_PY_DIR="$TEST_ROOT/broken-python"  # a python3 that always fails
mkdir -p "$GC_BIN_DIR" "$TOOLS" "$OLD_CLI_DIR" "$BROKEN_CLI_DIR" "$BROKEN_PY_DIR"

cat >"$GC_BIN_DIR/gc" <<'FAKE_GC'
#!/bin/bash
set -euo pipefail
[ "$*" = "config show --json" ] || { echo "fake gc: unexpected $*" >&2; exit 2; }
[ -f "$FAKE_CONFIG" ] || { echo "no city here" >&2; exit 1; }
pwd -P >"$FAKE_CONFIG.cwd"
cat "$FAKE_CONFIG"
FAKE_GC

cat >"$TOOLS/leonard_cli" <<'FAKE_CLI'
#!/bin/bash
# Records the HOME it ran under: the drive's HOME is the city, never the
# caller's.
printf '%s\n' "$HOME" >"$(dirname "$0")/home.log"
echo "Usage: leonard_cli [options]"
echo "    --gate-exit-codes    Exit 0/1/75 by verdict."
FAKE_CLI
cat >"$OLD_CLI_DIR/leonard_cli" <<'FAKE_OLD'
#!/bin/bash
echo "Usage: leonard_cli [options]"
FAKE_OLD
cat >"$BROKEN_CLI_DIR/leonard_cli" <<'FAKE_BROKEN'
#!/bin/bash
# A pub-cache wrapper that cannot find dart in the drive's environment.
echo "dart: command not found" >&2
exit 127
FAKE_BROKEN
cat >"$BROKEN_PY_DIR/python3" <<'FAKE_PY'
#!/bin/bash
echo "python3: broken" >&2
exit 1
FAKE_PY
cat >"$TOOLS/flutter" <<'FAKE_FLUTTER'
#!/bin/bash
[ "$*" = "devices --machine" ] || exit 2
[ "${FAKE_FLUTTER_RC:-0}" = 0 ] || exit "$FAKE_FLUTTER_RC"
cat "$FAKE_DEVICES"
FAKE_FLUTTER
cat >"$TOOLS/xcodebuild" <<'FAKE_XCODE'
#!/bin/bash
exit "${FAKE_XCODE_RC:-0}"
FAKE_XCODE
cat >"$TOOLS/adb" <<'FAKE_ADB'
#!/bin/bash
exit 0
FAKE_ADB
chmod +x "$GC_BIN_DIR/gc" "$TOOLS"/* "$OLD_CLI_DIR/leonard_cli" "$BROKEN_CLI_DIR/leonard_cli" "$BROKEN_PY_DIR/python3"

FAILURES=0
CASE=""
pass_case() { printf 'ok   %s\n' "$CASE"; }
fail_case() {
  printf 'FAIL %s: %s\n' "$CASE" "$*" >&2
  FAILURES=$((FAILURES + 1))
}
expect_exit() { [ "$EXIT" = "$1" ] || fail_case "exit $EXIT, want $1; output: $(cat "$CASE_DIR/out")"; }
expect_contains() { grep -qF -- "$1" "$CASE_DIR/out" || fail_case "output lacks: $1; output: $(cat "$CASE_DIR/out")"; }
expect_lacks() { if grep -qF -- "$1" "$CASE_DIR/out"; then fail_case "output has: $1"; fi; }
expect_first_line() {
  head -1 "$CASE_DIR/out" | grep -qF -- "$1" || fail_case "first line lacks: $1; got: $(head -1 "$CASE_DIR/out")"
}

new_case() {
  CASE="$1"
  CASE_DIR="$TEST_ROOT/$1"
  mkdir -p "$CASE_DIR/city"
  FAKE_CONFIG="$CASE_DIR/config.json"
  FAKE_DEVICES="$CASE_DIR/devices.json"
  printf '[{"id": "macos", "name": "macOS", "targetPlatform": "darwin", "emulator": false}, {"id": "emulator-5554", "name": "Pixel", "targetPlatform": "android-arm64", "emulator": true}]' >"$FAKE_DEVICES"
  # A good env file: the tools on PATH, a credential, unset vars expanding
  # empty. The check's environment is rebuilt from scratch, so the fakes'
  # knobs reach them through the env file, as real settings would.
  printf 'PATH=%s:"$PATH"\nANTHROPIC_API_KEY=test-key\nUNUSED="${NOT_SET_ANYWHERE}"\nFAKE_DEVICES=%s\n' \
    "$TOOLS" "$FAKE_DEVICES" >"$CASE_DIR/good.env"
  printf 'this_command_does_not_exist_xyz\n' >"$CASE_DIR/broken.env"
  # The PATH of whoever runs gc doctor. Cases that put $TOOLS on it prove the
  # checks discard the caller's PATH.
  CALLER_PATH="$GC_BIN_DIR:/usr/bin:/bin"
  rm -f "$TOOLS/home.log"
}

write_config() {
  # write_config <rigs-json>
  printf '{"schema_version": "1", "config": {"Rigs": %s}}' "$1" >"$FAKE_CONFIG"
}

vars() {
  # vars <key> <value> ... -> a JSON object. A helper, not an inline
  # "{...}" string: bash 3.2 brace-expands a "{a, b}" written inside
  # $(...) inside double quotes.
  local out="" sep=""
  while [ $# -gt 0 ]; do
    out="$out$sep\"$1\": \"$2\""
    sep=", "
    shift 2
  done
  printf '{%s}' "$out"
}

rig() {
  # rig <name> <formula-vars-json> [<imports-json>]
  local imports="${3:-}"
  [ -n "$imports" ] || imports='{}'
  printf '{"Name": "%s", "FormulaVars": %s, "Imports": %s}' "$1" "$2" "$imports"
}

LEONARD_IMPORT='{"leonard": {"Source": "https://github.com/memento-engineering/lenny/tree/main/gc_pack/leonard"}}'

run_doctor() {
  # run_doctor <check> [extra env...]: run the check as gc doctor would,
  # from the pack directory with the city and pack paths set
  set +e
  (
    cd "$PACK" &&
      env -i \
        PATH="$CALLER_PATH" \
        HOME="$CASE_DIR" \
        TMPDIR="$CASE_DIR" \
        GC_CITY_PATH="$CASE_DIR/city" \
        GC_PACK_DIR="$PACK" \
        FAKE_CONFIG="$FAKE_CONFIG" \
        FAKE_DEVICES="$FAKE_DEVICES" \
        "${@:2}" \
        /bin/bash "$PACK/doctor/$1/run.sh"
  ) >"$CASE_DIR/out" 2>&1
  EXIT=$?
  set -e
}

# ----- a healthy rig passes every check, reading the config in the city -----
for check in $CHECKS; do
  before=$FAILURES
  new_case "healthy-$check"
  write_config "[$(rig app "$(vars leonard_cli leonard_cli env_file "$CASE_DIR/good.env")" "$LEONARD_IMPORT")]"
  run_doctor "$check"
  expect_exit 0
  expect_lacks "could not read"
  grep -qxF "$CASE_DIR/city" "$FAKE_CONFIG.cwd" || fail_case "gc config show did not run in the city"
  [ "$FAILURES" -gt "$before" ] || pass_case
done

before=$FAILURES
new_case healthy-details
write_config "[$(rig app "$(vars leonard_cli leonard_cli env_file "$CASE_DIR/good.env")" "$LEONARD_IMPORT")]"
run_doctor leonard-cli
expect_first_line "leonard_cli resolves for every rig"
expect_contains "rig app: leonard_cli $TOOLS/leonard_cli"
expect_contains "drive PATH: gc $GC_BIN_DIR/gc"
# The drive's HOME is the city, never the caller's ($CASE_DIR).
grep -qxF "$CASE_DIR/city" "$TOOLS/home.log" ||
  fail_case "leonard_cli ran with HOME=$(cat "$TOOLS/home.log" 2>/dev/null), want $CASE_DIR/city"
run_doctor devices
expect_contains "rig app: macos (macOS, darwin device)"
expect_contains "rig app: emulator-5554 (Pixel, android-arm64 emulator)"
run_doctor platform-tools
expect_contains "rig app: flutter $TOOLS/flutter"
expect_contains "rig app: adb $TOOLS/adb"
[ "$FAILURES" -gt "$before" ] || pass_case

# ----- env-file ---------------------------------------------------------------
before=$FAILURES
new_case env-file-missing
write_config "[$(rig app "$(vars env_file "$CASE_DIR/nope.env")")]"
run_doctor env-file
expect_exit 2
expect_first_line "rig app: env_file $CASE_DIR/nope.env not found"
[ "$FAILURES" -gt "$before" ] || pass_case

before=$FAILURES
new_case env-file-broken
write_config "[$(rig app "$(vars env_file "$CASE_DIR/broken.env")")]"
run_doctor env-file
expect_exit 2
expect_first_line "env_file $CASE_DIR/broken.env fails to load"
# The other checks name env-file instead of reporting a misleading cause.
run_doctor leonard-cli
expect_exit 2
expect_first_line "its env_file does not load (see leonard:env-file)"
[ "$FAILURES" -gt "$before" ] || pass_case

before=$FAILURES
new_case env-file-unset
write_config "[$(rig app '{}' "$LEONARD_IMPORT")]"
run_doctor env-file
expect_exit 1
expect_first_line "rig app: no env_file"
[ "$FAILURES" -gt "$before" ] || pass_case

before=$FAILURES
new_case env-file-relative
write_config "[$(rig app "$(vars env_file gc.env)")]"
run_doctor env-file
expect_exit 1
expect_first_line "rig app: env_file gc.env is not an absolute path"
[ "$FAILURES" -gt "$before" ] || pass_case

before=$FAILURES
new_case env-file-in-city
cp "$CASE_DIR/good.env" "$CASE_DIR/city/gc.env"
write_config "[$(rig app "$(vars env_file "$CASE_DIR/city/gc.env")")]"
run_doctor env-file
expect_exit 1
expect_first_line "is inside the city"
[ "$FAILURES" -gt "$before" ] || pass_case

# ----- leonard-cli --------------------------------------------------------------
before=$FAILURES
new_case cli-not-on-check-path
# No env file: the check's PATH alone, where leonard_cli is not, although the
# caller's PATH has it.
CALLER_PATH="$TOOLS:$CALLER_PATH"
write_config "[$(rig app '{"leonard_cli": "leonard_cli"}')]"
run_doctor leonard-cli
expect_exit 2
expect_first_line "rig app: leonard_cli not found on the drive's PATH: leonard_cli"
[ "$FAILURES" -gt "$before" ] || pass_case

before=$FAILURES
new_case cli-fails-to-run
write_config "[$(rig app "$(vars leonard_cli "$BROKEN_CLI_DIR/leonard_cli")")]"
run_doctor leonard-cli
expect_exit 2
expect_first_line "--help fails to run (exit 127) in the drive's environment: dart: command not found"
expect_lacks "0.4.2 or later"
[ "$FAILURES" -gt "$before" ] || pass_case

before=$FAILURES
new_case cli-absolute-path
write_config "[$(rig app "$(vars leonard_cli "$TOOLS/leonard_cli")")]"
run_doctor leonard-cli
expect_exit 0
[ "$FAILURES" -gt "$before" ] || pass_case

before=$FAILURES
new_case cli-too-old
write_config "[$(rig app "$(vars leonard_cli "$OLD_CLI_DIR/leonard_cli")")]"
run_doctor leonard-cli
expect_exit 2
expect_first_line "does not support --gate-exit-codes"
[ "$FAILURES" -gt "$before" ] || pass_case

# ----- rig selection and the worst result -------------------------------------
before=$FAILURES
new_case two-rigs
# web does not use the pack and is skipped; app passes; ios fails, and the
# error heads the report.
write_config "[$(rig web '{"other_var": "x"}'), $(rig app "$(vars leonard_cli "$TOOLS/leonard_cli")"), $(rig ios "$(vars leonard_cli "$OLD_CLI_DIR/leonard_cli")" "$LEONARD_IMPORT")]"
run_doctor leonard-cli
expect_exit 2
expect_first_line "rig ios:"
expect_contains "rig app: leonard_cli $TOOLS/leonard_cli"
expect_lacks "rig web"
[ "$FAILURES" -gt "$before" ] || pass_case

before=$FAILURES
new_case no-rig-uses-pack
write_config "[$(rig web '{}')]"
run_doctor leonard-cli
expect_exit 2
expect_first_line "rig (formula defaults): leonard_cli not found"
expect_lacks "could not read"
[ "$FAILURES" -gt "$before" ] || pass_case

# ----- settings that cannot be read are never a silent OK ----------------------
# A rig whose env_file is missing would fail env-file; when its settings
# cannot be read, the check must not pass either.
for scenario in gc-fails gc-not-json gc-no-rigs gc-absent python-fails; do
  before=$FAILURES
  new_case "config-$scenario"
  write_config "[$(rig app "$(vars env_file "$CASE_DIR/nope.env")")]"
  case "$scenario" in
    gc-fails) rm -f "$FAKE_CONFIG"; want="gc config show --json failed" ;;
    gc-not-json) printf 'Welcome to gc!\n' >"$FAKE_CONFIG"; want="is not JSON" ;;
    gc-no-rigs) printf '{"schema_version": "1", "config": {}}' >"$FAKE_CONFIG"; want="has no config.Rigs" ;;
    gc-absent) CALLER_PATH="/usr/bin:/bin"; want="gc is not on PATH" ;;
    python-fails) CALLER_PATH="$BROKEN_PY_DIR:$CALLER_PATH"; want="could not parse gc config show --json: python3: broken" ;;
  esac
  run_doctor env-file
  [ "$EXIT" != 0 ] || fail_case "exit 0 although the settings could not be read: $(cat "$CASE_DIR/out")"
  expect_contains "warning: could not read the rigs' leonard settings"
  expect_contains "$want"
  expect_contains "rig (formula defaults)"
  [ "$FAILURES" -gt "$before" ] || pass_case
done

before=$FAILURES
new_case gc-absent-from-drive-path
CALLER_PATH="/usr/bin:/bin"
write_config "[$(rig app "$(vars leonard_cli "$TOOLS/leonard_cli")")]"
run_doctor leonard-cli
expect_exit 2
expect_contains "gc is not on the drive's PATH"
[ "$FAILURES" -gt "$before" ] || pass_case

before=$FAILURES
new_case problem-count
write_config "[$(rig a "$(vars env_file "$CASE_DIR/nope.env")"), $(rig b "$(vars env_file "$CASE_DIR/nope.env")")]"
run_doctor env-file
expect_exit 2
expect_first_line "(and 1 more)"
[ "$FAILURES" -gt "$before" ] || pass_case

# ----- platform-tools -----------------------------------------------------------
before=$FAILURES
new_case xcode-not-selected
cp "$CASE_DIR/good.env" "$CASE_DIR/no-xcode.env"
printf 'FAKE_XCODE_RC=1\n' >>"$CASE_DIR/no-xcode.env"
write_config "[$(rig app "$(vars env_file "$CASE_DIR/no-xcode.env")")]"
run_doctor platform-tools
expect_exit 1
expect_first_line "xcodebuild is present but no Xcode is selected"
[ "$FAILURES" -gt "$before" ] || pass_case

before=$FAILURES
new_case no-platform-tools
# The caller's PATH has every tool; the drive's does not.
CALLER_PATH="$TOOLS:$CALLER_PATH"
printf 'ANTHROPIC_API_KEY=test-key\n' >"$CASE_DIR/bare.env"
write_config "[$(rig app "$(vars env_file "$CASE_DIR/bare.env")")]"
run_doctor platform-tools
expect_exit 1
expect_first_line "rig app: flutter is not on the drive's PATH"
# macOS has a system /usr/bin/xcodebuild on the check's PATH; elsewhere
# neither tool is there.
if [ ! -e /usr/bin/xcodebuild ] && [ ! -e /usr/local/bin/xcodebuild ]; then
  expect_contains "neither Xcode (xcodebuild) nor the Android SDK (adb)"
fi
run_doctor devices
expect_exit 1
expect_first_line "no flutter on the drive's PATH"
[ "$FAILURES" -gt "$before" ] || pass_case

# ----- devices ------------------------------------------------------------------
before=$FAILURES
new_case first-run-banner
# Flutter's first run under a fresh HOME (the city) prints a banner on stdout
# after the JSON; text before it is tolerated too.
printf '  [notice]\n[{"id": "macos", "name": "macOS", "targetPlatform": "darwin"}]\n  Welcome to Flutter!\n  [telemetry notice]\n' >"$FAKE_DEVICES"
write_config "[$(rig app "$(vars env_file "$CASE_DIR/good.env")")]"
run_doctor devices
expect_exit 0
expect_contains "rig app: macos (macOS, darwin device)"
[ "$FAILURES" -gt "$before" ] || pass_case

before=$FAILURES
new_case no-devices
printf '[]' >"$FAKE_DEVICES"
write_config "[$(rig app "$(vars env_file "$CASE_DIR/good.env")")]"
run_doctor devices
expect_exit 1
expect_first_line "flutter sees no device"
[ "$FAILURES" -gt "$before" ] || pass_case

before=$FAILURES
new_case devices-not-a-list
printf '{"error": "not a list"}' >"$FAKE_DEVICES"
write_config "[$(rig app "$(vars env_file "$CASE_DIR/good.env")")]"
run_doctor devices
expect_exit 1
expect_first_line "flutter sees no device"
expect_lacks "Traceback"
[ "$FAILURES" -gt "$before" ] || pass_case

before=$FAILURES
new_case devices-fails
printf 'FAKE_FLUTTER_RC=1\n' >>"$CASE_DIR/good.env"
write_config "[$(rig app "$(vars env_file "$CASE_DIR/good.env")")]"
run_doctor devices
expect_exit 1
expect_first_line "rig app: flutter devices failed or timed out"
[ "$FAILURES" -gt "$before" ] || pass_case

if [ "$FAILURES" -gt 0 ]; then
  printf '%s doctor test case(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'all doctor tests passed\n'
