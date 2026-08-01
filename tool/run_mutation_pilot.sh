#!/usr/bin/env bash
set -euo pipefail

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_dir="$workspace_root/packages/leonard_native"
artifact_root="$workspace_root/artifacts/mutation/leonard_native"
mode="${1:-full}"

if [[ "$mode" != "dry" && "$mode" != "full" ]]; then
  echo "usage: $0 [dry|full]" >&2
  exit 64
fi

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
coverage_source="$workspace_root/artifacts/coverage/leonard_native.lcov"
if [[ -f "$coverage_source" ]]; then
  normalized_coverage="$output_dir/leonard_native.lcov"
  sed 's#^SF:packages/leonard_native/#SF:lib/#' \
    "$coverage_source" > "$normalized_coverage"
  mutation_args+=(--coverage "$normalized_coverage")
fi

dart run mutation_test "${mutation_args[@]}" 2>&1 | tee "$output_dir/console.txt"
