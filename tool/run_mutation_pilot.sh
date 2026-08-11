#!/usr/bin/env bash
set -euo pipefail
workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
mode="${1:-full}"; [[ $# -gt 0 ]] && shift
package="${1:-leonard_native}"; [[ $# -gt 0 ]] && shift
package_dir="$workspace_root/packages/$package"
[[ -d "$package_dir" ]] || { echo "unknown package: $package" >&2; exit 64; }

# Fork on package type: a pubspec declaring the flutter SDK dependency keeps the
# pre-rewrite local flutter-test mutation path; pure Dart delegates to the vended runner.
if grep -Eq '^[[:space:]]+flutter:[[:space:]]*$' "$package_dir/pubspec.yaml" \
   && grep -Eq '^[[:space:]]+sdk:[[:space:]]*flutter[[:space:]]*$' "$package_dir/pubspec.yaml"; then
  exec "$workspace_root/tool/run_mutation_flutter.sh" "$mode" "$package_dir" "$@"
fi

runner="$workspace_root/packages/leonard_cli/lib/assets/tools/leonard/run_mutation.sh"
args=("$mode" "$package_dir" --repo-root "$workspace_root")
coverage="$workspace_root/artifacts/coverage/$package.lcov"
[[ -f "$coverage" ]] && args+=(--coverage "$coverage")
[[ "${MUTATION_GATE:-0}" == 1 ]] && args+=(--gate)
[[ $# -gt 0 ]] && args+=(-- "$@")
exec "$runner" "${args[@]}"
