#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

check() {
  # check <rig> <leonard_cli> <env_file>
  local reason
  if [ -z "$3" ]; then
    warn "rig $1: no env_file; the drive gets the check's minimal PATH and no model credentials (set env_file in [rigs.formula_vars])"
    return
  fi
  if ! reason="$(env_file_loads "$3")"; then
    fail "rig $1: env_file $3 $reason"
    return
  fi
  case "$3" in
    "${GC_CITY_PATH:-/nonexistent}"/*)
      warn "rig $1: env_file $3 is inside the city, which is listable and backed up; keep credentials outside it"
      return
      ;;
  esac
  detail "rig $1: env_file $3 loads"
}

for_each_rig check
finish "env_file loads for every rig"
