#!/usr/bin/env bash
set -euo pipefail

# usage: run_mutation_pilot.sh [dry|full] [package]
#
# Mode stays argument one for backward compatibility: CI calls
# `run_mutation_pilot.sh full` and must keep working unchanged.

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="${1:-full}"
package="${2:-leonard_native}"

if [[ "$mode" != "dry" && "$mode" != "full" ]]; then
  echo "usage: $0 [dry|full] [package]" >&2
  exit 64
fi

package_dir="$workspace_root/packages/$package"
if [[ ! -d "$package_dir" ]]; then
  echo "no such package: $package (looked in $package_dir)" >&2
  exit 66
fi

artifact_root="$workspace_root/artifacts/mutation/$package"
output_dir="$artifact_root/$mode"
rm -rf "$output_dir"
mkdir -p "$output_dir"

cd "$package_dir"
if [[ "$mode" == "dry" ]]; then
  dart run mutation_test --dry --format none 2>&1 | tee "$output_dir/console.txt"
  exit 0
fi

dart test
mutation_args=(--format all --output "$output_dir")
coverage_source="$workspace_root/artifacts/coverage/$package.lcov"
if [[ -f "$coverage_source" ]]; then
  normalized_coverage="$output_dir/$package.lcov"
  sed "s#^SF:packages/$package/#SF:lib/#" \
    "$coverage_source" > "$normalized_coverage"
  mutation_args+=(--coverage "$normalized_coverage")
fi

dart run mutation_test "${mutation_args[@]}" 2>&1 | tee "$output_dir/console.txt"
