#!/usr/bin/env bash
# Offline test of tool/publish_guard.sh. A fake `curl`, first on PATH, serves
# every pub.dev read from tool/test_fixtures/publish_guard/pub_dev/ and refuses
# any other URL, so no case touches the network.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/tool/publish_guard.sh"
FIXTURES="$ROOT/tool/test_fixtures/publish_guard"
REPO="$FIXTURES/repo"
PUB_DEV="$FIXTURES/pub_dev"
readonly PUB_DEV_PREFIX='https://pub.dev/api/packages/'

[[ -x "$SCRIPT" ]] || {
  printf 'publish_guard_test: script is not executable: %s\n' "$SCRIPT" >&2
  exit 1
}
bash -n "$SCRIPT"

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/publish-guard-test.XXXXXX")"
cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

CURL_LOG="$TEST_ROOT/curl.log"
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/logs"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'set -euo pipefail'
  printf 'log=%q\n' "$CURL_LOG"
  printf 'pub_dev=%q\n' "$PUB_DEV"
  printf 'prefix=%q\n' "$PUB_DEV_PREFIX"
  printf '%s\n' 'url="${!#}"'
  printf '%s\n' 'printf "%s\n" "$url" >>"$log"'
  printf '%s\n' 'if [[ "$url" != "$prefix"* ]]; then'
  printf '%s\n' '  printf "fake curl: refusing %s\n" "$url" >&2'
  printf '%s\n' '  exit 2'
  printf '%s\n' 'fi'
  printf '%s\n' 'listing="$pub_dev/${url##*/}.json"'
  printf '%s\n' 'if [[ -f "$listing" ]]; then'
  printf '%s\n' '  cat "$listing"'
  printf '%s\n' 'else'
  printf '%s\n' '  printf "curl: (22) The requested URL returned error: 404\n" >&2'
  printf '%s\n' '  exit 22'
  printf '%s\n' 'fi'
} >"$TEST_ROOT/bin/curl"
chmod +x "$TEST_ROOT/bin/curl"
export PATH="$TEST_ROOT/bin:$PATH"

OUT="$TEST_ROOT/stdout"
ERR="$TEST_ROOT/stderr"
case_index=0
passed=0
status=0
case_name=''
case_log=''

# Runs the guard from the fixture repository root with arguments "$@",
# capturing its stdout, stderr, exit status and the pub.dev reads it made.
run_guard() {
  case_index=$((case_index + 1))
  case_log="$TEST_ROOT/logs/case-$case_index.log"
  : >"$CURL_LOG"
  set +e
  (cd "$REPO" && "$SCRIPT" "$@") >"$OUT" 2>"$ERR"
  status=$?
  set -e
  cp -f "$CURL_LOG" "$case_log"
}

pass() {
  passed=$((passed + 1))
  printf 'ok - %s\n' "$case_name"
}

fail_case() {
  printf 'not ok - %s\n' "$case_name"
  printf '# %s\n' "$1"
  printf '# exit status: %s\n' "$status"
  printf '# stdout:\n'
  sed 's/^/#   /' "$OUT"
  printf '# stderr:\n'
  sed 's/^/#   /' "$ERR"
  printf '# pub.dev reads:\n'
  sed 's/^/#   /' "$case_log"
  exit 1
}

expect_status() {
  [[ "$status" -eq "$1" ]] || fail_case "expected exit $1"
}

# Requires a line of file $1 beginning with $2 that contains each further
# argument as fixed text.
expect_line() {
  local file="$1" prefix="$2" line needle matched
  shift 2
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == "$prefix"* ]] || continue
    matched=1
    for needle in "$@"; do
      [[ "$line" == *"$needle"* ]] || matched=0
    done
    [[ "$matched" -eq 1 ]] && return 0
  done <"$file"
  fail_case "expected a line beginning '$prefix' in $(basename "$file")"
}

expect_empty() {
  [[ ! -s "$1" ]] || fail_case "expected $(basename "$1") to be empty"
}

# Requires the case's pub.dev reads to be exactly the given URLs, in order.
expect_reads() {
  local expected=''
  local url
  for url in "$@"; do
    expected="$expected$url"$'\n'
  done
  [[ "$(cat "$case_log")"$'\n' == "$expected" ||
    ("$#" -eq 0 && ! -s "$case_log") ]] ||
    fail_case "expected pub.dev reads: $*"
}

case_name='passes a tag whose version, changelog and siblings check out'
run_guard leonard_beta-v0.3.0 packages/leonard_beta
expect_status 0
expect_line "$OUT" 'publish_guard: PASS leonard_beta-v0.3.0'
expect_empty "$ERR"
expect_reads "${PUB_DEV_PREFIX}leonard_alpha"
pass

case_name='passes a prerelease tag'
run_guard leonard_epsilon-v0.5.0-dev.1
expect_status 0
expect_line "$OUT" 'publish_guard: PASS leonard_epsilon-v0.5.0-dev.1'
expect_reads
pass

case_name='passes a grid_assets package found without a directory argument'
run_guard leonard_grid_fixture-v0.1.0-rc.2
expect_status 0
expect_line "$OUT" 'publish_guard: PASS leonard_grid_fixture-v0.1.0-rc.2'
expect_reads "${PUB_DEV_PREFIX}leonard_alpha" "${PUB_DEV_PREFIX}leonard_beta"
pass

case_name='refuses a tag whose version differs from the pubspec'
run_guard leonard_beta-v0.3.1
expect_status 1
expect_line "$ERR" 'publish_guard: FAIL version:' 0.3.1 0.3.0
pass

case_name='refuses a version with no CHANGELOG heading'
run_guard leonard_gamma-v0.1.0
expect_status 1
expect_line "$ERR" 'publish_guard: FAIL changelog:'
pass

case_name='refuses a sibling whose declared version pub.dev does not list'
run_guard leonard_delta-v0.2.0
expect_status 1
expect_line "$ERR" 'publish_guard: FAIL dependency: leonard_epsilon 0.5.0-dev.1'
pass

case_name='refuses a sibling whose pub.dev listing cannot be read'
run_guard leonard_zeta-v0.1.0
expect_status 1
expect_line "$ERR" \
  "publish_guard: FAIL dependency: cannot read ${PUB_DEV_PREFIX}leonard_eta"
pass

case_name='refuses a pubspec that names another package'
run_guard leonard_alpha-v1.2.0 packages/leonard_beta
expect_status 1
expect_line "$ERR" 'publish_guard: FAIL name:'
pass

case_name='refuses a malformed tag'
run_guard leonard_alpha-1.2.0
expect_status 64
expect_line "$ERR" 'publish_guard: FAIL tag:'
pass

case_name='serves every pub.dev read from the fake curl'
cat "$TEST_ROOT"/logs/case-*.log >"$TEST_ROOT/all-reads.log"
case_log="$TEST_ROOT/all-reads.log"
[[ -s "$case_log" ]] || fail_case 'expected at least one pub.dev read'
while IFS= read -r url || [[ -n "$url" ]]; do
  [[ "$url" == "$PUB_DEV_PREFIX"* ]] ||
    fail_case "a read left pub.dev's package API: $url"
done <"$case_log"
pass

printf 'publish_guard_test: %s cases passed\n' "$passed"
