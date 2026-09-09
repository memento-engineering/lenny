#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/tool/select_mutation_files.sh"
MODE="${1:-all}"
case "$MODE" in
  all|diff|rotation) ;;
  *) printf 'usage: %s [all|diff|rotation]\n' "$0" >&2; exit 64 ;;
esac

[[ -x "$SCRIPT" ]] || {
  printf 'select_mutation_files_test: script is not executable: %s\n' "$SCRIPT" >&2
  exit 1
}
bash -n "$SCRIPT"

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/select-mutation-files-test.XXXXXX")"
FIXTURE="$TEST_ROOT/repo"
cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$FIXTURE/tool" "$FIXTURE/packages/fixture/lib"
cp -f "$SCRIPT" "$FIXTURE/tool/select_mutation_files.sh"
git -C "$FIXTURE" init -q -b main
git -C "$FIXTURE" config user.name 'Mutation Selector Test'
git -C "$FIXTURE" config user.email 'mutation-selector@example.invalid'

printf '%s\n' 'int existing = 0;' >"$FIXTURE/packages/fixture/lib/existing.dart"
git -C "$FIXTURE" add .
git -C "$FIXTURE" commit -qm 'branch point'
BRANCH_POINT="$(git -C "$FIXTURE" rev-parse HEAD)"

git -C "$FIXTURE" switch -qc feature
mkdir -p \
  "$FIXTURE/packages/fixture/test" \
  "$FIXTURE/packages/fixture/integration_test"
printf '%s\n' 'int a = 1;' >"$FIXTURE/packages/fixture/lib/a.dart"
printf '%s\n' 'int b = 2;' >"$FIXTURE/packages/fixture/lib/b.dart"
printf '%s\n' 'int c = 3;' >"$FIXTURE/packages/fixture/lib/c.dart"
printf '%s\n' 'void main() {}' >"$FIXTURE/packages/fixture/test/ignored.dart"
printf '%s\n' 'void main() {}' \
  >"$FIXTURE/packages/fixture/integration_test/ignored.dart"
git -C "$FIXTURE" add .
git -C "$FIXTURE" commit -qm 'feature changes'
FEATURE_TIP="$(git -C "$FIXTURE" rev-parse HEAD)"

git -C "$FIXTURE" switch -q main
printf '%s\n' 'int mainOnly = 4;' \
  >"$FIXTURE/packages/fixture/lib/main_only.dart"
git -C "$FIXTURE" add .
git -C "$FIXTURE" commit -qm 'main-only change'
MAIN_TIP="$(git -C "$FIXTURE" rev-parse HEAD)"

if [[ "$MODE" == all || "$MODE" == diff ]]; then
  DIFF_OUT="$TEST_ROOT/diff"
  "$FIXTURE/tool/select_mutation_files.sh" \
    fixture 2 "$MAIN_TIP" "$FEATURE_TIP" --out-dir "$DIFF_OUT" \
    >"$TEST_ROOT/diff.stdout" 2>"$TEST_ROOT/diff.stderr"

  printf '%s\n' 'lib/a.dart' 'lib/b.dart' >"$TEST_ROOT/diff.expected"
  cmp "$TEST_ROOT/diff.expected" "$TEST_ROOT/diff.stdout"
  ! grep -Fq 'main_only.dart' "$TEST_ROOT/diff.stdout"
  ! grep -Fq 'test/ignored.dart' "$TEST_ROOT/diff.stdout"
  ! grep -Fq 'integration_test/ignored.dart' "$TEST_ROOT/diff.stdout"
  grep -Fx 'Diff-selected files:' "$DIFF_OUT/selection.txt" >/dev/null
  grep -Fx 'Rotation-selected files:' "$DIFF_OUT/selection.txt" >/dev/null
  grep -Fx \
    'Selected 2 of 3 eligible files; the rest were NOT swept.' \
    "$DIFF_OUT/selection.txt" >/dev/null

  EMPTY_OUT="$TEST_ROOT/empty"
  "$FIXTURE/tool/select_mutation_files.sh" \
    fixture 2 "$FEATURE_TIP" "$FEATURE_TIP" --out-dir "$EMPTY_OUT" \
    >"$TEST_ROOT/empty.stdout" 2>"$TEST_ROOT/empty.stderr"
  [[ ! -s "$TEST_ROOT/empty.stdout" ]]
  grep -Fx 'No eligible changed fixture Dart files.' \
    "$TEST_ROOT/empty.stderr" >/dev/null
  grep -Fx 'No eligible changed fixture Dart files.' \
    "$EMPTY_OUT/console.txt" >/dev/null
  grep -Fx '(none)' "$EMPTY_OUT/selection.txt" >/dev/null
  printf 'select_mutation_files_test: diff PASS\n'
fi

if [[ "$MODE" == all || "$MODE" == rotation ]]; then
  git -C "$FIXTURE" switch -q feature
  ROTATE_ONE="$TEST_ROOT/rotate-one"
  ROTATE_TWO="$TEST_ROOT/rotate-two"
  "$FIXTURE/tool/select_mutation_files.sh" \
    fixture 1 "$BRANCH_POINT" "$FEATURE_TIP" --out-dir "$ROTATE_ONE" \
    --rotate 2 20260909 >"$TEST_ROOT/rotate-one.stdout"
  "$FIXTURE/tool/select_mutation_files.sh" \
    fixture 1 "$BRANCH_POINT" "$FEATURE_TIP" --out-dir "$ROTATE_TWO" \
    --rotate 2 20260909 >"$TEST_ROOT/rotate-two.stdout"
  cmp "$TEST_ROOT/rotate-one.stdout" "$TEST_ROOT/rotate-two.stdout"

  awk '
    /^Diff-selected files:$/ { section = "diff"; next }
    /^Rotation-selected files:$/ { section = "rotation"; next }
    /^Selected [0-9]+ of / { next }
    section == "diff" && $0 != "(none)" { print }
  ' "$ROTATE_ONE/selection.txt" >"$TEST_ROOT/rotation.diff"
  awk '
    /^Rotation-selected files:$/ { section = "rotation"; next }
    /^Selected [0-9]+ of / { next }
    section == "rotation" && $0 != "(none)" { print }
  ' "$ROTATE_ONE/selection.txt" >"$TEST_ROOT/rotation.slice"
  grep -Fx 'lib/a.dart' "$TEST_ROOT/rotation.diff" >/dev/null
  [[ "$(wc -l <"$TEST_ROOT/rotation.slice" | tr -d ' ')" == 2 ]]
  while IFS= read -r file; do
    ! grep -Fx -- "$file" "$TEST_ROOT/rotation.diff" >/dev/null
  done <"$TEST_ROOT/rotation.slice"
  [[ "$(sort "$TEST_ROOT/rotate-one.stdout" | uniq -d | wc -l | tr -d ' ')" == 0 ]]
  grep -Fx 'Diff-selected files:' "$ROTATE_ONE/selection.txt" >/dev/null
  grep -Fx 'Rotation-selected files:' "$ROTATE_ONE/selection.txt" >/dev/null

  : >"$TEST_ROOT/rotation.union"
  for seed in 20260909 20260910 20260911; do
    seed_out="$TEST_ROOT/seed-$seed"
    "$FIXTURE/tool/select_mutation_files.sh" \
      fixture 1 "$BRANCH_POINT" "$FEATURE_TIP" --out-dir "$seed_out" \
      --rotate 2 "$seed" >>"$TEST_ROOT/rotation.union"
  done
  sort -u "$TEST_ROOT/rotation.union" >"$TEST_ROOT/rotation.union.sorted"
  git -C "$FIXTURE" ls-tree -r --name-only "$FEATURE_TIP" \
    -- packages/fixture/lib |
    sed 's#^packages/fixture/##' |
    sort -u >"$TEST_ROOT/rotation.expected"
  cmp "$TEST_ROOT/rotation.expected" "$TEST_ROOT/rotation.union.sorted"
  printf 'select_mutation_files_test: rotation PASS\n'
fi

if [[ "$MODE" == all ]]; then
  printf 'select_mutation_files_test: PASS\n'
fi
