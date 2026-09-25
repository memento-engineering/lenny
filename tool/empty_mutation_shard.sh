#!/usr/bin/env bash
set -euo pipefail

# Writes the artifacts a shard with no assigned files must still upload, in
# whichever engine's shape the package's own mutation lane produces. Without
# them the upload fails on if-no-files-found and the aggregate job has nothing
# to join.
#
# The fork is the same one run_mutation_pilot.sh makes: a pubspec declaring the
# flutter SDK dependency stays on the pre-rewrite regex path, everything else
# runs butcher.

usage() {
  echo "usage: $0 PACKAGE ARTIFACT_DIR SHARD_INDEX SHARD_COUNT" >&2
  exit 64
}

[[ $# -eq 4 ]] || usage
package="$1"
artifact_dir="$2"
shard_index="$3"
shard_count="$4"
[[ "$package" =~ ^[a-z][a-z0-9_]*$ ]] || usage
[[ "$shard_index" =~ ^[0-9]+$ && "$shard_count" =~ ^[0-9]+$ ]] || usage

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
pubspec="$workspace_root/packages/$package/pubspec.yaml"
[[ -f "$pubspec" ]] || { echo "unknown package: $package" >&2; exit 66; }

mkdir -p "$artifact_dir"
printf 'No files assigned to shard %s of %s.\n' \
  "$shard_index" "$shard_count" > "$artifact_dir/console.txt"

if grep -Eq '^[[:space:]]+flutter:[[:space:]]*$' "$pubspec" \
   && grep -Eq '^[[:space:]]+sdk:[[:space:]]*flutter[[:space:]]*$' "$pubspec"; then
  printf '%s\n' \
    'Found 0 mutations in 0 source files!' \
    'Total tests: 0' \
    'Undetected Mutations: 0 (0.00%)' \
    'Not covered by tests: 0' >> "$artifact_dir/console.txt"
  printf '# Mutation report\n\nNo files were assigned to this shard.\n' \
    > "$artifact_dir/mutation-test-report.md"
  exit 0
fi

printf '%s\n' \
  'mutants=0' 'killed=0' 'survived=0' 'no_coverage=0' 'compile_error=0' \
  'runtime_error=0' 'timeout=0' 'ignored=0' 'pending=0' \
  'msi=none' 'covered_msi=none' > "$artifact_dir/summary.txt"
printf '%s\n' \
  '{"schemaVersion": "1", "thresholds": {"high": 80, "low": 60}, "files": {}}' \
  > "$artifact_dir/mutation-report.json"
printf '# Mutation report\n\nNo files were assigned to this shard.\n' \
  > "$artifact_dir/mutation-report.md"
