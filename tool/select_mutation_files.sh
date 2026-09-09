#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'usage: %s PACKAGE MAX_FILES BASE_SHA HEAD_SHA --out-dir DIR [--rotate N SEED]\n' "$0" >&2
  exit 64
}

[[ $# -ge 6 ]] || usage

PACKAGE="$1"
MAX_FILES="$2"
BASE_SHA="$3"
HEAD_SHA="$4"
shift 4

OUT_DIR=''
ROTATE_COUNT='0'
ROTATE_SEED=''
SEEN_OUT_DIR=false
SEEN_ROTATE=false

while (( $# > 0 )); do
  case "$1" in
    --out-dir)
      [[ "$SEEN_OUT_DIR" == false && $# -ge 2 && -n "$2" ]] || usage
      OUT_DIR="$2"
      SEEN_OUT_DIR=true
      shift 2
      ;;
    --rotate)
      [[ "$SEEN_ROTATE" == false && $# -ge 3 ]] || usage
      ROTATE_COUNT="$2"
      ROTATE_SEED="$3"
      SEEN_ROTATE=true
      shift 3
      ;;
    *) usage ;;
  esac
done

[[ -n "$PACKAGE" && -n "$BASE_SHA" && -n "$HEAD_SHA" ]] || usage
[[ "$MAX_FILES" =~ ^[0-9]+$ ]] || usage
[[ "$ROTATE_COUNT" =~ ^[0-9]+$ ]] || usage
[[ "$SEEN_OUT_DIR" == true ]] || usage

MAX_FILES_VALUE=$((10#$MAX_FILES))
ROTATE_COUNT_VALUE=$((10#$ROTATE_COUNT))

day_ordinal() {
  local seed="$1"
  local year month day max_day days_before_year days_before_month
  local leap=0

  [[ "$seed" =~ ^[0-9]{8}$ ]] || return 1
  year=$((10#${seed:0:4}))
  month=$((10#${seed:4:2}))
  day=$((10#${seed:6:2}))
  (( year >= 1 && month >= 1 && month <= 12 && day >= 1 )) || return 1

  if (( year % 400 == 0 || (year % 4 == 0 && year % 100 != 0) )); then
    leap=1
  fi
  case "$month" in
    1|3|5|7|8|10|12) max_day=31 ;;
    4|6|9|11) max_day=30 ;;
    2) max_day=$((28 + leap)) ;;
  esac
  (( day <= max_day )) || return 1

  days_before_year=$((365 * (year - 1) + (year - 1) / 4 - (year - 1) / 100 + (year - 1) / 400))
  case "$month" in
    1) days_before_month=0 ;;
    2) days_before_month=31 ;;
    3) days_before_month=$((59 + leap)) ;;
    4) days_before_month=$((90 + leap)) ;;
    5) days_before_month=$((120 + leap)) ;;
    6) days_before_month=$((151 + leap)) ;;
    7) days_before_month=$((181 + leap)) ;;
    8) days_before_month=$((212 + leap)) ;;
    9) days_before_month=$((243 + leap)) ;;
    10) days_before_month=$((273 + leap)) ;;
    11) days_before_month=$((304 + leap)) ;;
    12) days_before_month=$((334 + leap)) ;;
  esac
  printf '%s\n' "$((days_before_year + days_before_month + day - 1))"
}

ROTATE_DAY_ORDINAL=0
if [[ "$SEEN_ROTATE" == true ]]; then
  ROTATE_DAY_ORDINAL="$(day_ordinal "$ROTATE_SEED")" || usage
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO_ROOT"
mkdir -p -- "$OUT_DIR"
rm -f -- "$OUT_DIR/console.txt"

# THREE-dot. A two-dot `base head` diff also reports files that
# main gained after this branch was cut -- the PR looks like it
# reverted them -- so unrelated packages get mutation-tested and
# someone else's score fails this job. Three-dot diffs against the
# merge-base, which is what "changed by this PR" means.
mapfile -t eligible < <(
  git diff --name-only --diff-filter=ACMR "$BASE_SHA...$HEAD_SHA" |
    awk -v prefix="packages/$PACKAGE/" '
      index($0, prefix) == 1 {
        relative = substr($0, length(prefix) + 1)
        if (relative ~ /\.dart$/ && relative !~ /^(test|integration_test)\//) {
          print relative
        }
      }
    ' |
    sort -u
)

selected=("${eligible[@]:0:MAX_FILES_VALUE}")
if (( ${#eligible[@]} == 0 )); then
  selected=()
fi

rotation_selected=()
if (( ROTATE_COUNT_VALUE > 0 )); then
  mapfile -t rotation_candidates < <(
    git ls-tree -r --name-only "$HEAD_SHA" -- "packages/$PACKAGE/lib" |
      awk -v prefix="packages/$PACKAGE/" '
        index($0, prefix) == 1 && $0 ~ /\.dart$/ {
          print substr($0, length(prefix) + 1)
        }
      ' |
      sort -u
  )

  if (( ${#rotation_candidates[@]} > 0 )); then
    declare -A selected_lookup=()
    for file in "${selected[@]}"; do
      selected_lookup["$file"]=1
    done

    read -r list_hash _ < <(printf '%s\n' "${rotation_candidates[@]}" | cksum)
    start=$(((list_hash + ROTATE_DAY_ORDINAL * ROTATE_COUNT_VALUE) % ${#rotation_candidates[@]}))
    for ((examined = 0; examined < ${#rotation_candidates[@]}; examined++)); do
      index=$(((start + examined) % ${#rotation_candidates[@]}))
      file="${rotation_candidates[$index]}"
      if [[ -z "${selected_lookup[$file]+present}" ]]; then
        rotation_selected+=("$file")
        selected_lookup["$file"]=1
        (( ${#rotation_selected[@]} == ROTATE_COUNT_VALUE )) && break
      fi
    done
  fi
fi

{
  printf '%s\n' 'Diff-selected files:'
  if (( ${#selected[@]} == 0 )); then
    printf '%s\n' '(none)'
  else
    printf '%s\n' "${selected[@]}"
  fi
  printf '%s\n' 'Rotation-selected files:'
  if (( ${#rotation_selected[@]} == 0 )); then
    printf '%s\n' '(none)'
  else
    printf '%s\n' "${rotation_selected[@]}"
  fi
  if (( ${#eligible[@]} > MAX_FILES_VALUE )); then
    # Never truncate silently — a capped sweep that reads as full
    # coverage is worse than no sweep.
    printf 'Selected %s of %s eligible files; the rest were NOT swept.\n' \
      "$MAX_FILES" "${#eligible[@]}"
  fi
} >"$OUT_DIR/selection.txt"

combined=("${selected[@]}" "${rotation_selected[@]}")
if (( ${#combined[@]} == 0 )); then
  printf 'No eligible changed %s Dart files.\n' "$PACKAGE" |
    tee "$OUT_DIR/console.txt" >&2
  exit 0
fi

printf '%s\n' "${combined[@]}"
