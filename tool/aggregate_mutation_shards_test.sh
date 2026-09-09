#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
aggregator="$repo_root/tool/aggregate_mutation_shards.sh"
temporary="$(mktemp -d)"
cleanup() { rm -rf -- "$temporary"; }
trap cleanup EXIT

fail() { echo "aggregate_mutation_shards_test: $*" >&2; exit 1; }
assert_contains() {
  local needle="$1" file="$2"
  grep -Fq -- "$needle" "$file" || fail "missing '$needle' in $file"
}
assert_count() {
  local expected="$1" needle="$2" file="$3" actual
  actual="$(grep -Fc -- "$needle" "$file" || true)"
  [[ "$actual" == "$expected" ]] ||
    fail "expected $expected occurrences of '$needle' in $file, found $actual"
}
expect_exit() {
  local expected="$1"
  shift
  set +e
  "$@" >/dev/null 2>&1
  local status=$?
  set -e
  [[ "$status" == "$expected" ]] ||
    fail "expected exit $expected from '$*', found $status"
}

downloads="$temporary/downloads"
mkdir -p "$downloads"
write_shard() {
  local index="$1" file="$2" found="$3" undetected="$4" not_covered="$5"
  local shard="$downloads/mutation-leonard_native-full-shard-$index"
  mkdir -p "$shard"
  printf '%s\n' "$file" > "$shard/files.txt"
  printf 'selection from shard %s\n' "$index" > "$shard/selection.txt"
  printf 'Found %s mutations in 1 source files!\n' "$found" > "$shard/console.txt"
  printf 'Total tests: %s\n' "$found" >> "$shard/console.txt"
  printf 'Undetected Mutations: %s (ignored%%)\n' "$undetected" >> "$shard/console.txt"
  printf 'Not covered by tests: %s\n' "$not_covered" >> "$shard/console.txt"
  printf '# Mutation report\n\n## Undetected mutations in file : %s\n\nmutation %s\n' \
    "$file" "$index" > "$shard/mutation-test-report.md"
}

write_shard 0 lib/a.dart 3 1 1
write_shard 1 lib/b.dart 2 1 0
output="$temporary/output/mutation/leonard_native/full"
mkdir -p "$(dirname "$output")"
"$aggregator" leonard_native 2 "$downloads" "$output"

assert_contains 'Found 5 mutations across 2 file shards' "$output/console.txt"
assert_contains 'Total tests: 5' "$output/console.txt"
assert_contains 'Undetected Mutations: 2 (40.00%)' "$output/console.txt"
assert_contains 'Not covered by tests: 1' "$output/console.txt"
[[ "$(sed -n '1p' "$output/files.txt")" == 'lib/a.dart' ]] || fail 'first file row is out of order'
[[ "$(sed -n '2p' "$output/files.txt")" == 'lib/b.dart' ]] || fail 'second file row is out of order'
assert_count 1 '## Undetected mutations in file : lib/a.dart' "$output/mutation-test-report.md"
assert_count 1 '## Undetected mutations in file : lib/b.dart' "$output/mutation-test-report.md"
[[ -f "$output/shards/0/console.txt" && -f "$output/shards/1/console.txt" ]] ||
  fail 'raw shard reports were not preserved'
assert_contains 'selection from shard 0' "$output/selection.txt"

printf '%s\n' 'lib/a.dart' > "$downloads/mutation-leonard_native-full-shard-1/files.txt"
expect_exit 66 "$aggregator" leonard_native 2 "$downloads" "$temporary/duplicate"
printf '%s\n' 'lib/b.dart' > "$downloads/mutation-leonard_native-full-shard-1/files.txt"
printf '%s\n' 'Found two mutations' > "$downloads/mutation-leonard_native-full-shard-1/console.txt"
expect_exit 66 "$aggregator" leonard_native 2 "$downloads" "$temporary/malformed"
expect_exit 64 "$aggregator"
expect_exit 64 "$aggregator" 'Unsafe-Package' 2 "$downloads" "$temporary/unsafe"
expect_exit 64 "$aggregator" leonard_native 0 "$downloads" "$temporary/zero"
expect_exit 66 "$aggregator" leonard_native 3 "$downloads" "$temporary/missing"

# Binding acceptance probes: each load-bearing workflow fact gets an
# independent assertion so wrong matrix wiring cannot pass on "shard" alone.
workflow="$repo_root/.github/workflows/ci.yaml"
extract_job() {
  local job="$1" output_file="$2"
  awk -v target="  $job:" '
    $0 == target {inside = 1}
    inside && $0 != target && $0 ~ /^  [A-Za-z0-9_-]+:$/ {exit}
    inside {print}
  ' "$workflow" > "$output_file"
  [[ -s "$output_file" ]] || fail "workflow job not found: $job"
}

plan_job="$temporary/plan-job.yaml"
shard_job="$temporary/shard-job.yaml"
aggregate_job="$temporary/aggregate-job.yaml"
extract_job mutation-nightly-plan "$plan_job"
extract_job mutation-nightly "$shard_job"
extract_job mutation-nightly-aggregate "$aggregate_job"

assert_count 1 './tool/select_mutation_files.sh' "$workflow"
assert_count 1 './tool/select_mutation_files.sh' "$plan_job"
assert_contains 'for package in leonard_native leonard_contract leonard_flutter' "$plan_job"
assert_contains 'range(0; 3)' "$plan_job"
assert_contains 'package: "leonard_native", shard_index: ., shard_count: 3' "$plan_job"
assert_contains 'range(0; 1)' "$plan_job"
assert_contains 'package: "leonard_contract", shard_index: ., shard_count: 1' "$plan_job"
assert_contains 'range(0; 6)' "$plan_job"
assert_contains 'package: "leonard_flutter", shard_index: ., shard_count: 6' "$plan_job"
assert_contains 'MAX_FILES=0' "$plan_job"
assert_contains 'BASE_SHA=HEAD' "$plan_job"
assert_contains 'HEAD_SHA=HEAD' "$plan_job"
assert_contains '--rotate "$rotate_count"' "$plan_job"
plan_loop_line="$(grep -n 'for package in leonard_native' "$plan_job" | cut -d: -f1)"
plan_selector_line="$(grep -n './tool/select_mutation_files.sh' "$plan_job" | cut -d: -f1)"
plan_done_line="$(awk -v start="$plan_loop_line" 'NR > start && $0 ~ /^[[:space:]]+done$/ {print NR; exit}' "$plan_job")"
[[ "$plan_selector_line" -gt "$plan_loop_line" && "$plan_selector_line" -lt "$plan_done_line" ]] ||
  fail 'the single selector invocation must remain inside the three-package plan loop'

assert_contains 'needs: [coverage, mutation-nightly-plan]' "$shard_job"
assert_contains 'fromJSON(needs.mutation-nightly-plan.outputs.matrix)' "$shard_job"
assert_contains "awk -v shard_count=\"\$SHARD_COUNT\" -v shard_index=\"\$SHARD_INDEX\" '(NR-1) % shard_count == shard_index'" "$shard_job"
assert_contains 'if [[ "$PKG" == leonard_flutter ]]' "$shard_job"
assert_contains './tool/run_mutation_pilot.sh dry "$PKG" "${shard_files[@]}"' "$shard_job"
assert_contains './tool/run_mutation_pilot.sh full "$PKG" "${shard_files[@]}"' "$shard_job"
assert_contains 'name: mutation-${{ matrix.package }}-full-shard-${{ matrix.shard_index }}' "$shard_job"
assert_contains 'if-no-files-found: error' "$shard_job"
assert_count 0 './tool/select_mutation_files.sh' "$shard_job"

assert_contains 'needs: [mutation-nightly]' "$aggregate_job"
assert_contains 'if: always() &&' "$aggregate_job"
assert_contains 'package: leonard_native' "$aggregate_job"
assert_contains 'shard_count: 3' "$aggregate_job"
assert_contains 'package: leonard_contract' "$aggregate_job"
assert_contains 'shard_count: 1' "$aggregate_job"
assert_contains 'package: leonard_flutter' "$aggregate_job"
assert_contains 'shard_count: 6' "$aggregate_job"
assert_contains 'pattern: mutation-${{ matrix.package }}-full-shard-*' "$aggregate_job"
assert_contains './tool/aggregate_mutation_shards.sh' "$aggregate_job"
assert_contains "grep -Eq 'Not covered by tests: [0-9]+'" "$aggregate_job"
assert_contains 'name: mutation-${{ matrix.package }}-full' "$aggregate_job"
assert_contains 'path: artifacts/mutation/${{ matrix.package }}/full/' "$aggregate_job"
assert_contains 'retention-days: 14' "$aggregate_job"
assert_count 0 './tool/select_mutation_files.sh' "$aggregate_job"

flutter_dry_line="$(grep -n 'run_mutation_pilot.sh dry' "$shard_job" | cut -d: -f1)"
shard_full_line="$(grep -n 'run_mutation_pilot.sh full' "$shard_job" | cut -d: -f1)"
[[ -n "$flutter_dry_line" && -n "$shard_full_line" && "$shard_full_line" -gt "$flutter_dry_line" ]] ||
  fail 'the explicit Flutter dry sizing call must precede its full shard call'

flutter_exec_line="$(grep -n 'exec .*run_mutation_flutter.sh' "$repo_root/tool/run_mutation_pilot.sh" | cut -d: -f1)"
impact_line="$(grep -n -- 'args+=(--test-impact)' "$repo_root/tool/run_mutation_pilot.sh" | cut -d: -f1)"
[[ -n "$flutter_exec_line" && -n "$impact_line" && "$impact_line" -gt "$flutter_exec_line" ]] ||
  fail '--test-impact must remain after the immediate Flutter exec branch'

echo 'aggregate_mutation_shards_test: PASS'
