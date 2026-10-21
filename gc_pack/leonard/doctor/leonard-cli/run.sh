#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

check() {
  # check <rig> <leonard_cli> <env_file>
  local bin help
  if ! env_file_loads "$3" >/dev/null; then
    fail "rig $1: cannot look up leonard_cli, its env_file does not load (see leonard:env-file)"
    return
  fi
  bin="$(in_check_env "$3" command -v "$2" 2>/dev/null)" || {
    fail "rig $1: leonard_cli not found on the drive's PATH: $2 (set leonard_cli to an absolute path in [rigs.formula_vars], e.g. ~/.pub-cache/bin/leonard_cli)"
    return
  }
  help="$(in_check_env "$3" perl -e "$TIMEOUT_PL" 120 "$bin" --help 2>&1)"
  case "$help" in
    *--gate-exit-codes*) detail "rig $1: leonard_cli $bin" ;;
    *) fail "rig $1: $bin does not support --gate-exit-codes; the pack needs leonard_cli 0.4.2 or later (dart pub global activate leonard_cli)" ;;
  esac
}

for_each_rig check
finish "leonard_cli resolves for every rig"
