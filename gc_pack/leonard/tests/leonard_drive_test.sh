#!/usr/bin/env bash
set -euo pipefail

# Tests assets/scripts/checks/leonard-drive.sh against a fake gc and a fake
# leonard_cli, under a whitelisted environment like a Gas City check's. Runs
# the script with /bin/bash so macOS's bash 3.2 is covered.

PACK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$PACK/assets/scripts/checks/leonard-drive.sh"
[ -x "$SCRIPT" ] || {
  printf 'leonard_drive_test: script is not executable: %s\n' "$SCRIPT" >&2
  exit 1
}
bash -n "$SCRIPT"

TEST_ROOT="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/leonard-drive-test.XXXXXX")" && pwd -P)"
FAKE_BIN="$TEST_ROOT/bin"
mkdir -p "$FAKE_BIN"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

cat >"$FAKE_BIN/gc" <<'FAKE_GC'
#!/bin/bash
set -euo pipefail
case "$1 $2" in
  "bd show")
    file="$FAKE_DIR/beads/$3.json"
    [ -f "$file" ] || { echo "no such bead: $3" >&2; exit 1; }
    cat "$file"
    ;;
  "convoy status")
    cat "$FAKE_DIR/convoys/$3.json"
    ;;
  "bd update")
    shift 2
    printf '%s\n' "$@" >>"$FAKE_DIR/updates.log"
    ;;
  "bd comments")
    cp "$6" "$FAKE_DIR/comment-$4.txt"
    ;;
  *)
    echo "fake gc: unexpected $*" >&2
    exit 2
    ;;
esac
FAKE_GC

cat >"$FAKE_BIN/leonard_cli" <<'FAKE_LEONARD'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$@" >"$FAKE_DIR/leonard_args"
pwd -P >"$FAKE_DIR/leonard_cwd"
printf '%s' "${LEONARD_TEST_SECRET:-}" >"$FAKE_DIR/leonard_secret"
summary=""
while [ $# -gt 0 ]; do
  [ "$1" = --summary-json ] && summary="$2"
  shift
done
echo "model chatter that must stay out of the check's stderr" >&2
case "$FAKE_VERDICT" in
  pass) code=0 ;;
  fail) code=1 ;;
  infra) code=75 ;;
  crash) echo "boom" >&2; exit 3 ;;
esac
cat >"$summary" <<JSON
{"verdict": "$FAKE_VERDICT", "reason": "${FAKE_REASON:-fake $FAKE_VERDICT reason}", "exit_code": $code,
 "digest": ["#0 core.tap node_id=\"4\" → ok", "#1 core.done reason=\"x\" → ok"]}
JSON
exit "$code"
FAKE_LEONARD
chmod +x "$FAKE_BIN/gc" "$FAKE_BIN/leonard_cli"

FAILURES=0
CASE=""
pass_case() { printf 'ok   %s\n' "$CASE"; }
fail_case() {
  printf 'FAIL %s: %s\n' "$CASE" "$*" >&2
  FAILURES=$((FAILURES + 1))
}
expect_exit() { [ "$EXIT" = "$1" ] || fail_case "exit $EXIT, want $1; stderr: $(cat "$CASE_DIR/stderr")"; }
expect_contains() {
  # expect_contains <file> <text>
  grep -qF -- "$2" "$1" 2>/dev/null || fail_case "$1 lacks: $2"
}
expect_lacks() {
  if grep -qF -- "$2" "$1" 2>/dev/null; then fail_case "$1 has: $2"; fi
}

# new_case <name>: a fresh fake store with the standard bead graph
#   step s1 (root r1) -> root r1 (input convoy c1) -> convoy c1 -> input in1
new_case() {
  CASE="$1"
  CASE_DIR="$TEST_ROOT/$1"
  FAKE_DIR="$CASE_DIR/fake"
  mkdir -p "$FAKE_DIR/beads" "$FAKE_DIR/convoys" "$CASE_DIR/work" "$CASE_DIR/city"
  printf 'LEONARD_TEST_SECRET=from-env-file\n' >"$CASE_DIR/operator.env"
  STEP_META="\"gc.root_bead_id\": \"r1\", \"leonard.leonard_cli\": \"$FAKE_BIN/leonard_cli\", \"leonard.env_file\": \"$CASE_DIR/operator.env\", \"leonard.model\": \"claude\", \"leonard.model_id\": \"{{model_id}}\", \"leonard.wall_clock_minutes\": \"15\""
  write_bead s1 "step" "{$STEP_META}"
  write_bead r1 "root" '{"gc.input_convoy_id": "c1"}'
  printf '{"children": [{"id": "in1"}]}' >"$FAKE_DIR/convoys/c1.json"
  INPUT_DESCRIPTION="Open settings and turn on dark mode"
  INPUT_META='"leonard.vm_uri": "ws://127.0.0.1:5555/abc=/ws", "leonard.model": "openai", "leonard.leonard_cli": "/bin/false"'
}

write_bead() {
  printf '[{"id": "%s", "description": "%s", "metadata": %s}]' "$1" "$2" "$3" >"$FAKE_DIR/beads/$1.json"
}

run_check() {
  # run_check <fake-verdict> [extra env...]
  write_bead in1 "$INPUT_DESCRIPTION" "{$INPUT_META}"
  set +e
  env -i \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    HOME="$CASE_DIR" \
    TMPDIR="$CASE_DIR" \
    GC_BEAD_ID=s1 \
    GC_ITERATION=1 \
    GC_WORK_DIR="$CASE_DIR/work" \
    GC_CITY_PATH="$CASE_DIR/city" \
    GC_ARTIFACT_DIR="$CASE_DIR/molecule-scratch" \
    FAKE_DIR="$FAKE_DIR" \
    FAKE_VERDICT="$1" \
    "${@:2}" \
    /bin/bash "$SCRIPT" >"$CASE_DIR/stdout" 2>"$CASE_DIR/stderr"
  EXIT=$?
  set -e
}

# ----- pass: the input bead resolved through the convoy wins -----------------
new_case pass
run_check pass
expect_exit 0
expect_contains "$FAKE_DIR/leonard_args" "ws://127.0.0.1:5555/abc=/ws"
expect_contains "$FAKE_DIR/leonard_args" "--gate-exit-codes"
expect_contains "$FAKE_DIR/leonard_args" "openai"
expect_lacks "$FAKE_DIR/leonard_args" "--model-id"
expect_contains "$FAKE_DIR/leonard_secret" "from-env-file"
expect_contains "$FAKE_DIR/leonard_cwd" "$CASE_DIR/work"
expect_contains "$FAKE_DIR/updates.log" "in1"
expect_contains "$FAKE_DIR/updates.log" "leonard.verdict=pass"
expect_contains "$FAKE_DIR/updates.log" "leonard.reason=fake pass reason"
expect_contains "$FAKE_DIR/updates.log" "leonard.trajectory=$CASE_DIR/city/.leonard/runs/in1-1-"
expect_contains "$FAKE_DIR/comment-in1.txt" "leonard-drive pass (attempt 1): fake pass reason"
expect_contains "$FAKE_DIR/comment-in1.txt" "#1 core.done"
expect_contains "$CASE_DIR/stderr" "leonard-drive: pass — fake pass reason"
expect_lacks "$CASE_DIR/stderr" "model chatter"
find "$CASE_DIR/city" -name goal.txt -exec cat {} \; >"$CASE_DIR/goal"
expect_contains "$CASE_DIR/goal" "Open settings and turn on dark mode"
[ "$FAILURES" -gt 0 ] || pass_case

# ----- fail and infra pass the verdict through -------------------------------
for verdict in fail infra; do
  before=$FAILURES
  new_case "$verdict"
  run_check "$verdict"
  if [ "$verdict" = fail ]; then expect_exit 1; else expect_exit 75; fi
  expect_contains "$FAKE_DIR/updates.log" "leonard.verdict=$verdict"
  expect_contains "$CASE_DIR/stderr" "#0 core.tap"
  [ "$FAILURES" -gt "$before" ] || pass_case
done

# ----- a leonard_cli that dies without a verdict is infra --------------------
before=$FAILURES
new_case crash
run_check crash
expect_exit 75
expect_contains "$FAKE_DIR/updates.log" "leonard.verdict=infra"
expect_contains "$FAKE_DIR/updates.log" "leonard_cli exited 3"
[ "$FAILURES" -gt "$before" ] || pass_case

# ----- scenario and settings from bead metadata; launch mode -----------------
before=$FAILURES
new_case launch
INPUT_META='"leonard.scenario": "Sign in as demo", "leonard.device": "emulator-5554", "leonard.target": "lib/main.dart", "leonard.done_evidence": "Welcome", "leonard.wall_clock_minutes": 3'
run_check pass
expect_exit 0
expect_contains "$FAKE_DIR/leonard_args" "--launch"
expect_contains "$FAKE_DIR/leonard_args" "emulator-5554"
expect_contains "$FAKE_DIR/leonard_args" "lib/main.dart"
expect_contains "$FAKE_DIR/leonard_args" "--done-evidence-pattern"
expect_contains "$FAKE_DIR/leonard_args" "claude"
# bd returns numeric-looking metadata as a JSON number.
grep -A1 -x -- "--wall-clock-minutes" "$FAKE_DIR/leonard_args" | tail -1 >"$CASE_DIR/minutes"
expect_contains "$CASE_DIR/minutes" "3"
expect_lacks "$CASE_DIR/minutes" "15"
find "$CASE_DIR/city" -name goal.txt -exec cat {} \; >"$CASE_DIR/goal"
expect_contains "$CASE_DIR/goal" "Sign in as demo"
[ "$FAILURES" -gt "$before" ] || pass_case

# ----- missing settings are config errors, recorded as infra -----------------
before=$FAILURES
new_case no-scenario
INPUT_DESCRIPTION=""
run_check pass
expect_exit 64
expect_contains "$FAKE_DIR/updates.log" "leonard.verdict=infra"
expect_contains "$FAKE_DIR/updates.log" "leonard.reason=config: no scenario"
[ ! -f "$FAKE_DIR/leonard_args" ] || fail_case "leonard_cli ran"
[ "$FAILURES" -gt "$before" ] || pass_case

before=$FAILURES
new_case no-target
INPUT_META='"leonard.device": "emulator-5554"'
run_check pass
expect_exit 64
expect_contains "$CASE_DIR/stderr" "nothing to drive"
[ "$FAILURES" -gt "$before" ] || pass_case

# ----- infrastructure the check cannot reach --------------------------------
before=$FAILURES
new_case no-leonard
STEP_META="\"gc.root_bead_id\": \"r1\", \"leonard.leonard_cli\": \"$CASE_DIR/missing/leonard_cli\""
write_bead s1 "step" "{$STEP_META}"
run_check pass
expect_exit 75
expect_contains "$CASE_DIR/stderr" "leonard_cli not found"
# An infra exit replaces an earlier attempt's verdict.
expect_contains "$FAKE_DIR/updates.log" "leonard.verdict=infra"
expect_contains "$FAKE_DIR/updates.log" "leonard.reason=leonard_cli not found"
[ "$FAILURES" -gt "$before" ] || pass_case

before=$FAILURES
new_case no-env-file
rm "$CASE_DIR/operator.env"
run_check pass
expect_exit 75
expect_contains "$FAKE_DIR/updates.log" "leonard.verdict=infra"
expect_contains "$FAKE_DIR/updates.log" "leonard.reason=env_file not found"
[ "$FAILURES" -gt "$before" ] || pass_case

# ----- a broken env file is infra, and a working one cannot reach the script -
before=$FAILURES
new_case broken-env-file
printf 'PATH=/a b/bin:$PATH\n' >"$CASE_DIR/operator.env"
run_check pass
expect_exit 75
expect_contains "$CASE_DIR/stderr" "env_file failed to load"
expect_contains "$FAKE_DIR/updates.log" "leonard.verdict=infra"
[ ! -f "$FAKE_DIR/leonard_args" ] || fail_case "leonard_cli ran"
[ "$FAILURES" -gt "$before" ] || pass_case

before=$FAILURES
new_case scoped-env-file
printf 'LEONARD_TEST_SECRET=from-env-file\nVM_URI=ws://env-file/ws\nINPUT_ID=hijacked\nUNSET_TOO=$NOT_SET\n' >"$CASE_DIR/operator.env"
run_check pass
expect_exit 0
expect_contains "$FAKE_DIR/leonard_args" "ws://127.0.0.1:5555/abc=/ws"
expect_lacks "$FAKE_DIR/leonard_args" "ws://env-file/ws"
expect_contains "$FAKE_DIR/leonard_secret" "from-env-file"
expect_contains "$FAKE_DIR/updates.log" "in1"
expect_lacks "$FAKE_DIR/updates.log" "hijacked"
[ "$FAILURES" -gt "$before" ] || pass_case

# ----- a backtick in the reason is replaced, on bash 3.2 too -----------------
before=$FAILURES
new_case backtick
run_check fail FAKE_REASON='never tapped `Save`'
expect_exit 1
expect_contains "$FAKE_DIR/updates.log" "leonard.reason=never tapped 'Save'"
expect_lacks "$FAKE_DIR/updates.log" "\\'"
[ "$FAILURES" -gt "$before" ] || pass_case

before=$FAILURES
new_case unreadable-bead
rm "$FAKE_DIR/beads/r1.json"
run_check pass
expect_exit 75
expect_contains "$CASE_DIR/stderr" "gc bd show r1 --json failed"
[ "$FAILURES" -gt "$before" ] || pass_case

# ----- outside Gas City: LEONARD_INPUT_BEAD and env settings ------------------
before=$FAILURES
new_case direct
write_bead in1 "$INPUT_DESCRIPTION" '{"leonard.vm_uri": "ws://direct/ws"}'
set +e
env -i PATH="$FAKE_BIN:/usr/bin:/bin" HOME="$CASE_DIR" FAKE_DIR="$FAKE_DIR" FAKE_VERDICT=pass \
  LEONARD_INPUT_BEAD=in1 LEONARD_CLI="$FAKE_BIN/leonard_cli" LEONARD_ENV_FILE="$CASE_DIR/operator.env" \
  /bin/bash -c "cd '$CASE_DIR/work' && /bin/bash '$SCRIPT'" >"$CASE_DIR/stdout" 2>"$CASE_DIR/stderr"
EXIT=$?
set -e
expect_exit 0
expect_contains "$FAKE_DIR/leonard_args" "ws://direct/ws"
expect_contains "$FAKE_DIR/leonard_secret" "from-env-file"
expect_contains "$FAKE_DIR/updates.log" "leonard.trajectory=$CASE_DIR/work/.leonard/runs/in1-0-"
[ "$FAILURES" -gt "$before" ] || pass_case

# ----- outside Gas City the bead cannot choose the program or the env file ---
before=$FAILURES
new_case direct-hostile
printf '#!/bin/bash\ntouch "$FAKE_DIR/evil_ran"\n' >"$CASE_DIR/evil"
chmod +x "$CASE_DIR/evil"
printf 'touch "$FAKE_DIR/evil_sourced"\n' >"$CASE_DIR/evil.env"
write_bead in1 "$INPUT_DESCRIPTION" "{\"leonard.vm_uri\": \"ws://direct/ws\", \"leonard.leonard_cli\": \"$CASE_DIR/evil\", \"leonard.env_file\": \"$CASE_DIR/evil.env\", \"leonard.runs_dir\": \"$CASE_DIR/evil-runs\"}"
set +e
env -i PATH="$FAKE_BIN:/usr/bin:/bin" HOME="$CASE_DIR" FAKE_DIR="$FAKE_DIR" FAKE_VERDICT=pass \
  LEONARD_INPUT_BEAD=in1 LEONARD_CLI="$FAKE_BIN/leonard_cli" LEONARD_ENV_FILE="$CASE_DIR/operator.env" \
  /bin/bash -c "cd '$CASE_DIR/work' && /bin/bash '$SCRIPT'" >"$CASE_DIR/stdout" 2>"$CASE_DIR/stderr"
EXIT=$?
set -e
expect_exit 0
[ ! -e "$FAKE_DIR/evil_ran" ] || fail_case "the bead's leonard_cli ran"
[ ! -e "$FAKE_DIR/evil_sourced" ] || fail_case "the bead's env_file was sourced"
[ ! -e "$CASE_DIR/evil-runs" ] || fail_case "the bead's runs_dir was used"
expect_contains "$FAKE_DIR/leonard_secret" "from-env-file"
[ "$FAILURES" -gt "$before" ] || pass_case

if [ "$FAILURES" -gt 0 ]; then
  printf '%s failure(s)\n' "$FAILURES" >&2
  exit 1
fi
printf 'all leonard-drive cases passed\n'
