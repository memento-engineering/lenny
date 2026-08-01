#!/usr/bin/env bash
set -euo pipefail

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact_dir="$workspace_root/artifacts/coverage"
coverage_packages='^leonard_'

dart_packages=(
  leonard_agent
  leonard_cli
  leonard_contract
  leonard_host
  leonard_native
  leonard_tmux
)
flutter_packages=(
  leonard_flutter
  leonard_devtools
  leonard_dio
  leonard_riverpod
  leonard_router
)

rm -rf "$artifact_dir"
mkdir -p "$artifact_dir"

for package in "${dart_packages[@]}"; do
  package_dir="$workspace_root/packages/$package"
  raw_dir="$package_dir/coverage"
  rm -rf "$raw_dir"
  (
    cd "$package_dir"
    dart test test --coverage="$raw_dir"
    dart run coverage:format_coverage \
      --package="$package_dir" \
      --report-on="$workspace_root/packages" \
      --base-directory="$workspace_root" \
      --in="$raw_dir" \
      --lcov \
      --out="$artifact_dir/$package.lcov"
  )
done

for package in "${flutter_packages[@]}"; do
  package_dir="$workspace_root/packages/$package"
  raw_lcov="$package_dir/coverage/lcov.info"
  rm -rf "$package_dir/coverage"
  (
    cd "$package_dir"
    flutter test test \
      --coverage \
      --coverage-package="$coverage_packages" \
      --coverage-path="$raw_lcov"
  )
  lcov \
    --quiet \
    --base-directory "$workspace_root" \
    --add-tracefile "$raw_lcov" \
    --substitute "s#^$workspace_root/##" \
    --substitute "s#^lib/#packages/$package/lib/#" \
    --substitute 's#^\.\./(leonard_[^/]+)/#packages/$1/#' \
    --output-file "$artifact_dir/$package.lcov"
done

trace_args=()
for package in "${dart_packages[@]}" "${flutter_packages[@]}"; do
  trace_args+=(--add-tracefile "$artifact_dir/$package.lcov")
done
lcov \
  --quiet \
  --base-directory "$workspace_root" \
  "${trace_args[@]}" \
  --output-file "$artifact_dir/workspace.lcov"

for report in "$artifact_dir"/*.lcov; do
  lcov --quiet --list "$report" >/dev/null
  if grep '^SF:' "$report" | grep -qv '^SF:packages/'; then
    echo "non-workspace source path in $report" >&2
    exit 1
  fi
done
