#!/usr/bin/env bash
set -euo pipefail

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

for ((index = 0; index < shard_count_value; index++)); do
  shard="$download_root/mutation-$package-full-shard-$index"
  [[ -d "$shard" ]] || die 66 "expected shard directory not found: $shard"
  for required in console.txt files.txt mutation-test-report.md; do
    [[ -f "$shard/$required" ]] ||
      die 66 "expected shard file not found: $shard/$required"
  done
done

stage="$(mktemp -d "$output_parent/.mutation-$package-aggregate.XXXXXX")"
cleanup() {
  [[ -z "${stage:-}" ]] || rm -rf -- "$stage"
}
trap cleanup EXIT
mkdir -p "$stage/shards"
: > "$stage/files.txt"
: > "$stage/section-headers.txt"
printf '# Mutation report\n\nAggregate for `%s` across %s file shards.\n\n' \
  "$package" "$shard_count_value" > "$stage/mutation-test-report.md"

found_sum=0
total_sum=0
undetected_sum=0
not_covered_sum=0
selection_copied=0

for ((index = 0; index < shard_count_value; index++)); do
  shard="$download_root/mutation-$package-full-shard-$index"
  cp -Rf "$shard" "$stage/shards/$index"
  if (( ! selection_copied )) && [[ -f "$shard/selection.txt" ]]; then
    cp -f "$shard/selection.txt" "$stage/selection.txt"
    selection_copied=1
  fi
  while IFS= read -r file || [[ -n "$file" ]]; do
    [[ -z "$file" ]] || printf '%s\n' "$file" >> "$stage/files.txt"
  done < "$shard/files.txt"

  console="$shard/console.txt"
  found="$(awk '$1 == "Found" && $2 ~ /^[0-9]+$/ && $3 == "mutations" {value = $2} END {if (value == "") exit 1; print value}' "$console")" ||
    die 66 "malformed Found summary: $console"
  total="$(awk '$1 == "Total" && $2 == "tests:" && $3 ~ /^[0-9]+$/ {value = $3} END {if (value == "") exit 1; print value}' "$console")" ||
    die 66 "malformed Total summary: $console"
  undetected="$(awk '$1 == "Undetected" && $2 == "Mutations:" && $3 ~ /^[0-9]+$/ {value = $3} END {if (value == "") exit 1; print value}' "$console")" ||
    die 66 "malformed Undetected summary: $console"
  not_covered="$(awk '$1 == "Not" && $2 == "covered" && $3 == "by" && $4 == "tests:" && $5 ~ /^[0-9]+$/ {value = $5} END {if (value == "") exit 1; print value}' "$console")" ||
    die 66 "malformed not-covered summary: $console"

  found_value=$((10#$found))
  total_value=$((10#$total))
  undetected_value=$((10#$undetected))
  not_covered_value=$((10#$not_covered))
  (( found_value == total_value )) ||
    die 66 "Found/Total mismatch in $console: $found_value != $total_value"
  found_sum=$((found_sum + found_value))
  total_sum=$((total_sum + total_value))
  undetected_sum=$((undetected_sum + undetected_value))
  not_covered_sum=$((not_covered_sum + not_covered_value))

  sed -n '/^## Undetected mutations in file :/p' \
    "$shard/mutation-test-report.md" >> "$stage/section-headers.txt"
  awk '
    /^## Undetected mutations in file :/ {copy = 1}
    copy {print}
  ' "$shard/mutation-test-report.md" >> "$stage/mutation-test-report.md"
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

rm -rf -- "$output_dir"
mv -f "$stage" "$output_dir"
stage=""
