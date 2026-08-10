#!/usr/bin/env bash
set -euo pipefail
workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
mode="${1:-full}"; [[ $# -gt 0 ]] && shift
package="${1:-leonard_native}"; [[ $# -gt 0 ]] && shift
runner="$workspace_root/packages/leonard_cli/lib/assets/tools/leonard/run_mutation.sh"
args=("$mode" "$workspace_root/packages/$package" --repo-root "$workspace_root")
coverage="$workspace_root/artifacts/coverage/$package.lcov"
[[ -f "$coverage" ]] && args+=(--coverage "$coverage")
[[ "${MUTATION_GATE:-0}" == 1 ]] && args+=(--gate)
[[ $# -gt 0 ]] && args+=(-- "$@")
exec "$runner" "${args[@]}"
