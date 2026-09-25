#!/usr/bin/env bash
set -euo pipefail

# Drives butcher, the AST mutation engine, behind this runner's own interface:
# the same three modes, the same flags, the same artifact layout under
# artifacts/mutation/<package>/<phase>. Only the engine changed.
#
# Two things about butcher shape the body. Its configuration is exclude-only,
# so a per-file selection is expressed as its complement in a generated
# butcher.yaml at the package root, removed again by a trap. And it has no
# sizing-only mode, so the dry phase hands it an lcov that records nothing:
# every mutant routes to noCoverage, which enumerates the selection without
# evaluating a single mutant.

usage() {
  echo "usage: $0 [dry|full|pr] PACKAGE_PATH [--repo-root PATH] [--coverage LCOV] [--rules XML]... [--test-impact] [--gate] [-- FILE...]" >&2
}
die() { local code="$1"; shift; echo "error: $*" >&2; exit "$code"; }

mode="${1:-}"; package_arg="${2:-}"
[[ "$mode" =~ ^(dry|full|pr)$ ]] || { usage; exit 64; }
[[ -n "$package_arg" ]] || { usage; exit 64; }
shift 2
repo_arg=""; coverage_arg=""; gate=0; test_impact=0; rules=(); files=()
while (( $# )); do
  case "$1" in
    --repo-root) (( $# >= 2 )) || die 64 "--repo-root requires a path"; repo_arg="$2"; shift 2 ;;
    --coverage) (( $# >= 2 )) || die 64 "--coverage requires a path"; coverage_arg="$2"; shift 2 ;;
    --rules) (( $# >= 2 )) || die 64 "--rules requires a path"; rules+=("$2"); shift 2 ;;
    --test-impact) test_impact=1; shift ;;
    --gate) gate=1; shift ;;
    --) shift; files=("$@"); break ;;
    *) die 64 "unknown argument: $1" ;;
  esac
done
[[ "$mode" != pr || ${#files[@]} -gt 0 ]] || die 64 "pr mode needs at least one package-relative file"
package_dir="$(cd "$package_arg" 2>/dev/null && pwd -P)" || die 66 "package path not found: $package_arg"
[[ -f "$package_dir/pubspec.yaml" ]] || die 66 "pubspec.yaml not found under $package_dir"
grep -qE '^[[:space:]]+flutter:[[:space:]]*$' "$package_dir/pubspec.yaml" &&
  die 65 "Flutter packages are unverified; this runner supports pure Dart only"
package_name="$(sed -n 's/^name:[[:space:]]*//p' "$package_dir/pubspec.yaml" | head -1)"
[[ -n "$package_name" ]] || die 65 "pubspec.yaml has no package name"
[[ "$package_name" =~ ^[a-z][a-z0-9_]*$ ]] || die 65 "unsafe package name: $package_name"
repo_root=""
if [[ -n "$repo_arg" ]]; then
  repo_root="$(cd "$repo_arg" 2>/dev/null && pwd -P)" || die 66 "repository root not found: $repo_arg"
fi
if [[ -z "$repo_root" ]]; then
  probe="$package_dir"
  while [[ "$probe" != "/" && ! -e "$probe/.git" ]]; do probe="$(dirname "$probe")"; done
  [[ -e "$probe/.git" ]] || die 66 "repository root not found; pass --repo-root"
  repo_root="$probe"
fi
for rule in "${rules[@]}"; do [[ -f "$rule" ]] || die 66 "rules file not found: $rule"; done
# The rules seam belonged to the regex engine: butcher's mutators are built in
# and its scope is configured by exclusion. Saying so beats accepting a file
# that would silently change nothing about the measurement.
(( ${#rules[@]} == 0 )) ||
  die 65 "--rules describes the retired regex engine; butcher's mutators are built in"
[[ -z "$coverage_arg" || -f "$coverage_arg" ]] || die 66 "coverage file not found: $coverage_arg"
excludes_tool="$repo_root/tool/butcher_excludes.dart"
summary_tool="$repo_root/tool/butcher_report_summary.dart"
[[ -f "$excludes_tool" ]] || die 66 "exclusion generator not found: $excludes_tool"
[[ -f "$summary_tool" ]] || die 66 "report summary tool not found: $summary_tool"
if (( test_impact )); then
  (( ${#files[@]} > 0 )) || die 64 "--test-impact needs at least one package-relative source"
fi

generated_excludes=""
cleanup() { [[ -z "$generated_excludes" ]] || rm -f -- "$generated_excludes"; }
trap cleanup EXIT HUP INT TERM

run_phase() {
  local phase="$1"; shift
  local inputs=("$@")
  local output="$repo_root/artifacts/mutation/$package_name/$phase"
  case "$output" in "$repo_root"/artifacts/mutation/*) ;; *) die 70 "unsafe artifact path: $output" ;; esac
  rm -rf -- "$output"; mkdir -p "$output"

  # The generated configuration belongs to this run alone; the trap removes it
  # even when the run is interrupted, so a checkout never carries one around.
  dart run "$excludes_tool" "$package_dir" "${inputs[@]}" > "$output/excludes.txt" ||
    die 70 "exclusion generation failed"
  generated_excludes="$package_dir/butcher.yaml"

  local report="$output/mutation-report.json"
  local args=(--output "$report")
  local status normalized
  if [[ "$phase" == dry ]]; then
    : > "$output/empty.lcov"
    args+=(--coverage "$output/empty.lcov")
  elif (( test_impact )); then
    echo "note: --test-impact routes each mutant to its covering tests; butcher collects that itself."
  elif [[ -n "$coverage_arg" ]]; then
    normalized="$output/$package_name.lcov"
    sed "s#^SF:packages/$package_name/#SF:#" "$coverage_arg" > "$normalized"
    args+=(--coverage "$normalized")
  else
    echo "note: no LCOV supplied; butcher collects its own coverage."
  fi
  args+=("$package_dir")
  set +e
  (cd "$package_dir" && dart run butcher:butcher "${args[@]}") 2>&1 | tee -a "$output/console.txt"
  status=${PIPESTATUS[0]}
  set -e
  if [[ -f "$report" ]]; then
    dart run "$summary_tool" "$report" --markdown "$output/mutation-report.md" \
      > "$output/summary.txt" || die 70 "report summary failed"
  fi
  return "$status"
}

if [[ "$mode" == dry ]]; then
  run_phase dry "${files[@]}" || { status=$?; (( gate )) && exit "$status"; echo "Reporting only (gating off)."; }
  exit 0
fi
run_phase dry "${files[@]}" || true
grep -qE '^mutants=[1-9][0-9]*$' \
  "$repo_root/artifacts/mutation/$package_name/dry/summary.txt" 2>/dev/null ||
  die 70 "dry sizing failed"
run_phase "$mode" "${files[@]}" || {
  status=$?
  (( gate )) && exit "$status"
  echo "butcher exited $status; reporting only (gating off)."
}
