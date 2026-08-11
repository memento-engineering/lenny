#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"; package_arg="${2:-}"
case "$mode" in dry | full | pr) ;; *) echo "usage: $0 [dry|full|pr] PACKAGE_PATH [file...]" >&2; exit 64 ;; esac
[[ -n "$package_arg" ]] || { echo "usage: $0 [dry|full|pr] PACKAGE_PATH [file...]" >&2; exit 64; }
shift 2
files=("$@")
package_dir="$(cd "$package_arg" 2>/dev/null && pwd -P)" || { echo "package path not found: $package_arg" >&2; exit 66; }
[[ -f "$package_dir/pubspec.yaml" ]] || { echo "pubspec.yaml not found under $package_dir" >&2; exit 66; }
[[ "$mode" != pr || ${#files[@]} -gt 0 ]] || { echo "pr mode needs at least one package-relative file" >&2; exit 64; }
workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
package="$(sed -n 's/^name:[[:space:]]*//p' "$package_dir/pubspec.yaml" | head -1)"
[[ -n "$package" ]] || { echo "pubspec.yaml has no package name" >&2; exit 65; }

output_dir="$workspace_root/artifacts/mutation/$package/$mode"
rm -rf -- "$output_dir"
mkdir -p "$output_dir"
rules="$output_dir/mutation_rules.xml"
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<mutations version="1.2"><commands><command group="test" expected-return="0" working-directory=".">flutter test</command></commands></mutations>' > "$rules"
mutation_args=(--rules "$rules" -b)

if [[ "$mode" == dry ]]; then
  mutation_args+=(--dry --format none)
else
  (cd "$package_dir" && flutter test)
  mutation_args+=(--format all --output "$output_dir")
  coverage_source="$workspace_root/artifacts/coverage/$package.lcov"
  if [[ -f "$coverage_source" ]]; then
    normalized_coverage="$output_dir/$package.lcov"
    sed "s#^SF:packages/$package/#SF:lib/#" "$coverage_source" > "$normalized_coverage"
    mutation_args+=(--coverage "$normalized_coverage")
  else
    echo "note: no lcov at $coverage_source — running without coverage input."
  fi
fi
[[ ${#files[@]} -gt 0 ]] && mutation_args+=("${files[@]}")

set +e
(cd "$package_dir" && dart run mutation_test "${mutation_args[@]}") 2>&1 | tee "$output_dir/console.txt"
status=${PIPESTATUS[0]}
set -e
if (( status != 0 )); then
  echo "mutation_test exited $status — the score is below its quality threshold."
  if [[ "${MUTATION_GATE:-0}" == 1 ]]; then
    echo "MUTATION_GATE=1 — failing this run."
    exit "$status"
  fi
  echo "Reporting only (gating off). Set MUTATION_GATE=1 to fail on score."
fi
