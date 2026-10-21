# Shared by the leonard doctor checks. Sourced, not run.
#
# A doctor check runs with the full environment of whoever ran `gc doctor`,
# but leonard-drive.sh runs as a Gas City check: a whitelisted environment
# with a minimal PATH and HOME set to the city, then the env file sourced on
# top. A doctor that looked at the caller's own PATH would pass on a machine
# where the drive still fails, so these checks rebuild the check's
# environment and resolve each rig's machine settings (leonard_cli,
# env_file) from the resolved city config, as the drive's step would see
# them.
#
# Pack doctor protocol: exit 0 OK, 1 warning, 2 error; the first stdout line
# is the message, the rest are details.

# The leonard-drive formula's var defaults (formulas/leonard-drive.toml).
LEONARD_CLI_DEFAULT=leonard_cli

add_dir() {
  # add_dir <path-list> <dir> -> the list with <dir> appended once
  case ":$1:" in
    *":$2:"*) printf '%s' "$1" ;;
    *) printf '%s' "${1:+$1:}$2" ;;
  esac
}

check_path() {
  # The PATH Gas City gives a check script: the directories of bd, gc, dolt
  # and jq, then /usr/local/bin:/usr/bin:/bin.
  local dirs="" name found dir
  for name in bd gc dolt jq; do
    found="$(command -v "$name" 2>/dev/null)" || continue
    case "$found" in /*) ;; *) continue ;; esac
    dirs="$(add_dir "$dirs" "$(dirname "$found")")"
  done
  for dir in /usr/local/bin /usr/bin /bin; do
    dirs="$(add_dir "$dirs" "$dir")"
  done
  printf '%s' "$dirs"
}

CHECK_PATH="$(check_path)"

in_check_env() {
  # in_check_env <env-file> <command...> -> run the command the way the
  # drive's in_env does: the check's environment, then the env file sourced
  # with its variables exported. A file that fails to load fails the command.
  local env_file="$1"
  shift
  env -i \
    PATH="$CHECK_PATH" \
    HOME="${GC_CITY_PATH:-$HOME}" \
    TMPDIR="${TMPDIR:-/tmp}" \
    LEONARD_DOCTOR_ENV_FILE="$env_file" \
    /bin/bash -c '
      if [ -n "$LEONARD_DOCTOR_ENV_FILE" ]; then
        set +u -a
        . "$LEONARD_DOCTOR_ENV_FILE" || exit 1
        set -u +a
      fi
      unset LEONARD_DOCTOR_ENV_FILE
      "$@"' in_check_env "$@" </dev/null
}

# perl -e "$TIMEOUT_PL" <seconds> <command...> runs the command and kills it
# after <seconds>: macOS ships no timeout(1). A program, not a function, so it
# also works inside in_check_env.
TIMEOUT_PL='alarm shift; exec @ARGV or exit 127'

with_timeout() {
  # with_timeout <seconds> <command...>
  perl -e "$TIMEOUT_PL" "$@"
}

CONFIG_NOTE=""

machine_settings() {
  # One line per rig that uses this pack: "<rig><TAB><leonard_cli><TAB><env_file>",
  # read from `gc config show --json` in the city. A rig uses the pack when
  # one of its imports is the leonard pack or its formula_vars set
  # leonard_cli or env_file. With no such rig, or no readable config, one
  # line of the formula defaults; CONFIG_NOTE then says why.
  local config=""
  if [ -n "${GC_CITY_PATH:-}" ] && command -v gc >/dev/null 2>&1; then
    config="$(cd "$GC_CITY_PATH" && with_timeout 60 gc config show --json 2>/dev/null </dev/null)" || config=""
  fi
  if [ -z "$config" ]; then
    CONFIG_NOTE="could not read the resolved city config (gc config show --json); checked the formula defaults"
    printf '(formula defaults)\t%s\t\n' "$LEONARD_CLI_DEFAULT"
    return
  fi
  printf '%s' "$config" | python3 -c '
import json
import sys

default_cli = sys.argv[1]


def get(obj, *keys):
    for key in keys:
        if isinstance(obj, dict) and key in obj:
            return obj[key]
    return None


try:
    payload = json.load(sys.stdin)
except Exception:
    payload = {}
config = get(payload, "config") or {}
rows = []
for rig in get(config, "Rigs", "rigs") or []:
    variables = get(rig, "FormulaVars", "formula_vars") or {}
    imports = get(rig, "Imports", "imports") or {}
    uses = "leonard_cli" in variables or "env_file" in variables
    for binding, entry in imports.items():
        source = str(get(entry, "Source", "source") or "").rstrip("/")
        if binding == "leonard" or source.endswith("gc_pack/leonard"):
            uses = True
    if uses:
        rows.append((
            str(get(rig, "Name", "name") or "?"),
            str(variables.get("leonard_cli") or default_cli),
            str(variables.get("env_file") or ""),
        ))
if not rows:
    rows.append(("(formula defaults)", default_cli, ""))
for row in rows:
    print("\t".join(value.replace("\t", " ") for value in row))
' "$LEONARD_CLI_DEFAULT"
}

env_file_loads() {
  # env_file_loads <env-file> -> 0 when the file is empty-named or loads;
  # otherwise 1 with the reason on stdout
  [ -n "$1" ] || return 0
  [ -f "$1" ] || {
    printf 'not found'
    return 1
  }
  local err
  err="$(in_check_env "$1" true 2>&1 >/dev/null)" || {
    printf 'fails to load: %s' "$(printf '%s' "$err" | tail -c 300 | tr '\n' ' ')"
    return 1
  }
}

STATUS=0
HEAD=""
DETAILS=""

detail() {
  DETAILS="${DETAILS}$*
"
}

warn() {
  # warn <message>: a warning; the worst finding heads the report
  if [ "$STATUS" -lt 1 ]; then
    STATUS=1
    HEAD="$1"
  fi
  detail "warning: $1"
}

fail() {
  # fail <message>: an error; the worst finding heads the report
  if [ "$STATUS" -lt 2 ]; then
    STATUS=2
    HEAD="$1"
  fi
  detail "error: $1"
}

finish() {
  # finish <ok-message>: print the report and exit with the worst status.
  # The heading names the worst finding and how many problems there are; the
  # details list every rig's result, the heading's included.
  local problems
  problems="$(printf '%s' "$DETAILS" | grep -cE '^(warning|error): ')"
  if [ "$problems" -gt 1 ]; then
    HEAD="$HEAD (and $((problems - 1)) more)"
  fi
  printf '%s\n' "${HEAD:-$1}"
  [ -z "$CONFIG_NOTE" ] || printf 'note: %s\n' "$CONFIG_NOTE"
  printf '%s' "$DETAILS"
  exit "$STATUS"
}

for_each_rig() {
  # for_each_rig <function>: call <function> <rig> <leonard_cli> <env_file>
  # once per machine-settings line
  # A file, not $(...), so machine_settings can set CONFIG_NOTE here.
  local rows rig cli env_file
  rows="$(mktemp "${TMPDIR:-/tmp}/leonard-doctor.XXXXXX")"
  machine_settings >"$rows"
  while IFS=$'\t' read -r rig cli env_file; do
    [ -n "$rig" ] || continue
    "$1" "$rig" "$cli" "$env_file"
  done <"$rows"
  rm -f "$rows"
}
