#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 [dry|full|pr] PACKAGE_PATH [--repo-root PATH] [--coverage LCOV] [--rules XML]... [--gate] [-- FILE...]" >&2
}
die() { local code="$1"; shift; echo "error: $*" >&2; exit "$code"; }

mode="${1:-}"; package_arg="${2:-}"
[[ "$mode" =~ ^(dry|full|pr)$ ]] || { usage; exit 64; }
[[ -n "$package_arg" ]] || { usage; exit 64; }
shift 2
repo_arg=""; coverage_arg=""; gate=0; rules=(); files=()
while (( $# )); do
  case "$1" in
    --repo-root) (( $# >= 2 )) || die 64 "--repo-root requires a path"; repo_arg="$2"; shift 2 ;;
    --coverage) (( $# >= 2 )) || die 64 "--coverage requires a path"; coverage_arg="$2"; shift 2 ;;
    --rules) (( $# >= 2 )) || die 64 "--rules requires a path"; rules+=("$2"); shift 2 ;;
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
[[ -z "$coverage_arg" || -f "$coverage_arg" ]] || die 66 "coverage file not found: $coverage_arg"

run_phase() {
  local phase="$1"; shift
  local output="$repo_root/artifacts/mutation/$package_name/$phase"
  case "$output" in "$repo_root"/artifacts/mutation/*) ;; *) die 70 "unsafe artifact path: $output" ;; esac
  rm -rf -- "$output"; mkdir -p "$output"
  local command_rules="$output/command_rules.xml"
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<mutations version="1.2"><commands><command group="test" expected-return="0" working-directory=".">dart test</command></commands></mutations>' > "$command_rules"
  local args=(--rules "$command_rules" -b)
  local absolute_rule normalized status
  : > "$output/semantic-rules.txt"
  for rule in "${rules[@]}"; do
    absolute_rule="$(cd "$(dirname "$rule")" && pwd -P)/$(basename "$rule")"
    args+=(--rules "$absolute_rule")
    sed -n 's/.* id="\([^"]*\)".*/semantic rule: \1/p' "$absolute_rule" |
      tee -a "$output/semantic-rules.txt"
  done
  if [[ "$phase" == dry ]]; then
    args+=(--dry --format none)
  else
    args+=(--format all --output "$output")
    if [[ -n "$coverage_arg" ]]; then
      normalized="$output/$package_name.lcov"
      sed "s#^SF:packages/$package_name/#SF:#" "$coverage_arg" > "$normalized"
      args+=(--coverage "$normalized")
    else
      echo "note: no LCOV supplied; running without coverage input."
    fi
  fi
  args+=("$@")
  set +e
  (cd "$package_dir" && dart run mutation_test "${args[@]}") 2>&1 | tee -a "$output/console.txt"
  status=${PIPESTATUS[0]}
  set -e
  return "$status"
}

if [[ "$mode" == dry ]]; then
  run_phase dry "${files[@]}" || { status=$?; (( gate )) && exit "$status"; echo "Reporting only (gating off)."; }
  exit 0
fi
run_phase dry "${files[@]}" || die 70 "dry sizing failed"
(cd "$package_dir" && dart test)
run_phase "$mode" "${files[@]}" || {
  status=$?
  (( gate )) && exit "$status"
  echo "mutation_test exited $status; reporting only (gating off)."
}
