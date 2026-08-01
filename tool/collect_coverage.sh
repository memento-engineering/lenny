#!/usr/bin/env bash
set -euo pipefail

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact_dir="$workspace_root/artifacts/coverage"
coverage_packages='^leonard_'

if [[ "${1:-}" == "dart-package" ]]; then
  raw_dir="$MELOS_PACKAGE_PATH/coverage"
  rm -rf "$raw_dir"
  dart test --coverage="$raw_dir"
  dart run coverage:format_coverage \
    --package="$MELOS_PACKAGE_PATH" \
    --report-on="$COVERAGE_WORKSPACE_ROOT/packages" \
    --base-directory="$COVERAGE_WORKSPACE_ROOT" \
    --in="$raw_dir" \
    --lcov \
    --out="$COVERAGE_ARTIFACT_DIR/$MELOS_PACKAGE_NAME.lcov"
  exit
fi

if [[ "${1:-}" == "flutter-package" ]]; then
  raw_lcov="$MELOS_PACKAGE_PATH/coverage/lcov.info"
  rm -rf "$MELOS_PACKAGE_PATH/coverage"
  flutter test \
    --coverage \
    --coverage-package="$COVERAGE_PACKAGES" \
    --coverage-path="$raw_lcov"
  if ! grep -q '^SF:' "$raw_lcov"; then
    flutter test --coverage --coverage-path="$raw_lcov"
  fi

  normalized_lcov="$raw_lcov.normalized"
  while IFS= read -r line; do
    if [[ "$line" == SF:* ]]; then
      source_path="${line#SF:}"
      if [[ "$source_path" != /* ]]; then
        source_path="$(cd "$MELOS_PACKAGE_PATH" && realpath "$source_path")"
      fi
      line="SF:${source_path#"$COVERAGE_WORKSPACE_ROOT"/}"
    fi
    printf '%s\n' "$line"
  done <"$raw_lcov" >"$normalized_lcov"
  mv -f "$normalized_lcov" "$raw_lcov"

  lcov \
    --quiet \
    --ignore-errors empty \
    --base-directory "$COVERAGE_WORKSPACE_ROOT" \
    --add-tracefile "$raw_lcov" \
    --output-file "$COVERAGE_ARTIFACT_DIR/$MELOS_PACKAGE_NAME.lcov"
  exit
fi

rm -rf "$artifact_dir"
mkdir -p "$artifact_dir"

export COVERAGE_WORKSPACE_ROOT="$workspace_root"
export COVERAGE_ARTIFACT_DIR="$artifact_dir"
export COVERAGE_PACKAGES="$coverage_packages"

dart run melos exec --no-flutter --fail-fast -- \
  "$workspace_root/tool/collect_coverage.sh dart-package"

dart run melos exec --flutter --fail-fast -- \
  "$workspace_root/tool/collect_coverage.sh flutter-package"

trace_args=()
for report in "$artifact_dir"/*.lcov; do
  trace_args+=(--add-tracefile "$report")
done
lcov \
  --quiet \
  --ignore-errors empty,unused \
  --base-directory "$workspace_root" \
  "${trace_args[@]}" \
  --output-file "$artifact_dir/workspace.lcov"

for report in "$artifact_dir"/*.lcov; do
  test -s "$report"
  lcov --quiet --list "$report" >/dev/null
  if grep '^SF:' "$report" | grep -qv '^SF:packages/'; then
    echo "non-workspace source path in $report" >&2
    exit 1
  fi
done
