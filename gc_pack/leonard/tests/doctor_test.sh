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
mkdir -p "$GC_BIN_DIR" "$TOOLS" "$OLD_CLI_DIR"

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
echo "Usage: leonard_cli [options]"
echo "    --gate-exit-codes    Exit 0/1/75 by verdict."
FAKE_CLI
cat >"$OLD_CLI_DIR/leonard_cli" <<'FAKE_OLD'
#!/bin/bash
echo "Usage: leonard_cli [options]"
FAKE_OLD
cat >"$TOOLS/flutter" <<'FAKE_FLUTTER'
#!/bin/bash
[ "$*" = "devices --machine" ] || exit 2
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
chmod +x "$GC_BIN_DIR/gc" "$TOOLS"/* "$OLD_CLI_DIR/leonard_cli"

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
        PATH="$GC_BIN_DIR:/usr/bin:/bin" \
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
  expect_lacks "note:"
  grep -qxF "$CASE_DIR/city" "$FAKE_CONFIG.cwd" || fail_case "gc config show did not run in the city"
  [ "$FAILURES" -gt "$before" ] || pass_case
done

before=$FAILURES
new_case healthy-details
write_config "[$(rig app "$(vars leonard_cli leonard_cli env_file "$CASE_DIR/good.env")" "$LEONARD_IMPORT")]"
run_doctor leonard-cli
expect_first_line "leonard_cli resolves for every rig"
expect_contains "rig app: leonard_cli $TOOLS/leonard_cli"
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
# No env file: the check's PATH alone, where leonard_cli is not.
write_config "[$(rig app '{"leonard_cli": "leonard_cli"}')]"
run_doctor leonard-cli
expect_exit 2
expect_first_line "rig app: leonard_cli not found on the drive's PATH: leonard_cli"
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
expect_lacks "note:"
[ "$FAILURES" -gt "$before" ] || pass_case

before=$FAILURES
new_case config-unreadable
# No config file: gc config show fails, and the checks say they fell back.
run_doctor env-file
expect_exit 1
expect_contains "note: could not read the resolved city config"
expect_contains "rig (formula defaults)"
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

if [ "$FAILURES" -gt 0 ]; then
  printf '%s doctor test case(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'all doctor tests passed\n'
