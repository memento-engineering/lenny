#!/usr/bin/env bash
set -euo pipefail

# Joins one package's per-file mutation shards into the canonical report.
#
# Two engines produce shards. A pure-Dart package runs butcher and every shard
# carries summary.txt and a Stryker JSON report; leonard_flutter still runs the
# regex engine and its shards carry that tool's console summary and Markdown.
# The mode is read off the shards themselves and must be the same for all of
# them, so a half-migrated download can never be summed into one number.
#
# The output console summary keeps its four lines whichever mode produced it:
# the workflow's coverage proof and anything else downstream reads those.

usage() {
  echo "usage: $0 PACKAGE SHARD_COUNT DOWNLOAD_ROOT OUTPUT_DIR" >&2
  exit 64
}
die() { local code="$1"; shift; echo "error: $*" >&2; exit "$code"; }

[[ $# -eq 4 ]] || usage
package="$1"
shard_count="$2"
download_arg="$3"
output_arg="$4"

[[ "$package" =~ ^[a-z][a-z0-9_]*$ ]] || die 64 "unsafe package name: $package"
[[ "$shard_count" =~ ^[0-9]+$ ]] || die 64 "shard count must be a positive integer"
shard_count_value=$((10#$shard_count))
(( shard_count_value > 0 )) || die 64 "shard count must be a positive integer"

download_root="$(cd "$download_arg" 2>/dev/null && pwd -P)" ||
  die 66 "download root not found: $download_arg"
output_parent_arg="$(dirname "$output_arg")"
output_name="$(basename "$output_arg")"
[[ -d "$output_parent_arg" ]] || die 66 "output parent not found: $output_parent_arg"
[[ -n "$output_name" && "$output_name" != . && "$output_name" != / ]] ||
  die 64 "unsafe output directory: $output_arg"
output_parent="$(cd "$output_parent_arg" && pwd -P)"
output_dir="$output_parent/$output_name"
[[ "$output_dir" != "$download_root" ]] ||
  die 64 "output directory must differ from download root"

shard_path() { printf '%s/mutation-%s-full-shard-%s' "$download_root" "$package" "$1"; }

engine=""
for ((index = 0; index < shard_count_value; index++)); do
  shard="$(shard_path "$index")"
  [[ -d "$shard" ]] || die 66 "expected shard directory not found: $shard"
  if [[ -f "$shard/summary.txt" ]]; then
    shard_engine=butcher
    required=(console.txt files.txt summary.txt mutation-report.json mutation-report.md)
  else
    shard_engine=legacy
    required=(console.txt files.txt mutation-test-report.md)
  fi
  [[ -z "$engine" || "$engine" == "$shard_engine" ]] ||
    die 66 "shards mix engines: $shard is $shard_engine, earlier shards are $engine"
  engine="$shard_engine"
  for file in "${required[@]}"; do
    [[ -f "$shard/$file" ]] || die 66 "expected shard file not found: $shard/$file"
  done
done

# One `key=value` line from a shard summary, as a non-negative integer.
summary_value() {
  local file="$1" key="$2"
  awk -F= -v key="$key" '
    $1 == key && $2 ~ /^[0-9]+$/ {value = $2}
    END {if (value == "") exit 1; print value}
  ' "$file" || die 66 "malformed $key in $file"
}

stage="$(mktemp -d "$output_parent/.mutation-$package-aggregate.XXXXXX")"
cleanup() {
  [[ -z "${stage:-}" ]] || rm -rf -- "$stage"
}
trap cleanup EXIT
mkdir -p "$stage/shards"
: > "$stage/files.txt"
: > "$stage/section-headers.txt"

if [[ "$engine" == butcher ]]; then
  shard_roll_up=mutation-report.md
  section='^## Surviving mutants in '
else
  shard_roll_up=mutation-test-report.md
  section='^## Undetected mutations in file :'
fi
roll_up="$stage/$shard_roll_up"
printf '# Mutation report\n\nAggregate for `%s` across %s file shards.\n\n' \
  "$package" "$shard_count_value" > "$roll_up"

found_sum=0
total_sum=0
undetected_sum=0
not_covered_sum=0
killed_sum=0
selection_copied=0
reports=()

for ((index = 0; index < shard_count_value; index++)); do
  shard="$(shard_path "$index")"
  cp -Rf "$shard" "$stage/shards/$index"
  if (( ! selection_copied )) && [[ -f "$shard/selection.txt" ]]; then
    cp -f "$shard/selection.txt" "$stage/selection.txt"
    selection_copied=1
  fi
  while IFS= read -r file || [[ -n "$file" ]]; do
    [[ -z "$file" ]] || printf '%s\n' "$file" >> "$stage/files.txt"
  done < "$shard/files.txt"

  if [[ "$engine" == butcher ]]; then
    summary="$shard/summary.txt"
    found_value="$(summary_value "$summary" mutants)"
    total_value="$found_value"
    undetected_value="$(summary_value "$summary" survived)"
    not_covered_value="$(summary_value "$summary" no_coverage)"
    killed_sum=$((killed_sum + $(summary_value "$summary" killed)))
    reports+=("$shard/mutation-report.json")
  else
    console="$shard/console.txt"
    found_value="$(awk '$1 == "Found" && $2 ~ /^[0-9]+$/ && $3 == "mutations" {value = $2} END {if (value == "") exit 1; print value}' "$console")" ||
      die 66 "malformed Found summary: $console"
    total_value="$(awk '$1 == "Total" && $2 == "tests:" && $3 ~ /^[0-9]+$/ {value = $3} END {if (value == "") exit 1; print value}' "$console")" ||
      die 66 "malformed Total summary: $console"
    undetected_value="$(awk '$1 == "Undetected" && $2 == "Mutations:" && $3 ~ /^[0-9]+$/ {value = $3} END {if (value == "") exit 1; print value}' "$console")" ||
      die 66 "malformed Undetected summary: $console"
    not_covered_value="$(awk '$1 == "Not" && $2 == "covered" && $3 == "by" && $4 == "tests:" && $5 ~ /^[0-9]+$/ {value = $5} END {if (value == "") exit 1; print value}' "$console")" ||
      die 66 "malformed not-covered summary: $console"
    found_value=$((10#$found_value))
    total_value=$((10#$total_value))
    undetected_value=$((10#$undetected_value))
    not_covered_value=$((10#$not_covered_value))
  fi

  (( found_value == total_value )) ||
    die 66 "Found/Total mismatch in shard $index: $found_value != $total_value"
  found_sum=$((found_sum + found_value))
  total_sum=$((total_sum + total_value))
  undetected_sum=$((undetected_sum + undetected_value))
  not_covered_sum=$((not_covered_sum + not_covered_value))

  sed -n "/$section/p" "$shard/$shard_roll_up" >> "$stage/section-headers.txt"
  awk -v section="$section" '
    $0 ~ section {copy = 1}
    copy {print}
  ' "$shard/$shard_roll_up" >> "$roll_up"
done

duplicate_file="$(LC_ALL=C sort "$stage/files.txt" | awk '
  previous == $0 && $0 != "" && duplicate == "" {duplicate = $0}
  {previous = $0}
  END {print duplicate}
')"
[[ -z "$duplicate_file" ]] || die 66 "source appears in multiple shards: $duplicate_file"
duplicate_section="$(LC_ALL=C sort "$stage/section-headers.txt" | awk '
  previous == $0 && $0 != "" && duplicate == "" {duplicate = $0}
  {previous = $0}
  END {print duplicate}
')"
[[ -z "$duplicate_section" ]] ||
  die 66 "Markdown section appears more than once: $duplicate_section"
rm -f -- "$stage/section-headers.txt"

percentage="$(LC_ALL=C awk -v undetected="$undetected_sum" -v total="$total_sum" '
  BEGIN {
    if (total == 0) printf "0.00"
    else printf "%.2f", 100 * undetected / total
  }
')"
printf 'Found %s mutations across %s file shards\n' \
  "$found_sum" "$shard_count_value" > "$stage/console.txt"
printf 'Total tests: %s\n' "$total_sum" >> "$stage/console.txt"
printf 'Undetected Mutations: %s (%s%%)\n' \
  "$undetected_sum" "$percentage" >> "$stage/console.txt"
printf 'Not covered by tests: %s\n' "$not_covered_sum" >> "$stage/console.txt"

if [[ "$engine" == butcher ]]; then
  # The honest pair of scores: uncovered mutants lower the MSI and leave the
  # covered-code MSI intact, and timed-out mutants score in neither term.
  LC_ALL=C awk -v killed="$killed_sum" -v survived="$undetected_sum" \
    -v uncovered="$not_covered_sum" '
    function score(part, whole) {
      return whole == 0 ? "none" : sprintf("%.2f%%", 100 * part / whole)
    }
    BEGIN {
      printf "MSI: %s\n", score(killed, killed + survived + uncovered)
      printf "Covered-code MSI: %s\n", score(killed, killed + survived)
    }
  ' >> "$stage/console.txt"
  jq -s '{
    schemaVersion: (.[0].schemaVersion // "1"),
    thresholds: (.[0].thresholds // {high: 80, low: 60}),
    files: (map(.files) | add // {})
  }' "${reports[@]}" > "$stage/mutation-report.json" ||
    die 66 "could not merge the shard reports"
fi

rm -rf -- "$output_dir"
mv -f "$stage" "$output_dir"
stage=""
