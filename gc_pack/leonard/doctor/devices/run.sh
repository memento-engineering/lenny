#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

# Lists what `flutter devices` sees from the drive's environment, which is
# what a device/target run's `flutter run -d <device>` can target. As with
# platform-tools, a gap is a warning: vm_uri runs need no device here.

check() {
  # check <rig> <leonard_cli> <env_file>
  local json devices line
  if ! env_file_loads "$3" >/dev/null; then
    fail "rig $1: cannot list devices, its env_file does not load (see leonard:env-file)"
    return
  fi
  if ! in_check_env "$3" command -v flutter >/dev/null 2>&1; then
    warn "rig $1: no flutter on the drive's PATH, so no devices were listed (see leonard:platform-tools)"
    return
  fi
  json="$(in_check_env "$3" perl -e "$TIMEOUT_PL" 120 flutter devices --machine 2>/dev/null)" || {
    warn "rig $1: flutter devices failed or timed out"
    return
  }
  devices="$(printf '%s' "$json" | python3 -c '
import json
import sys

# The first time Flutter runs under a new HOME, which a fresh city is, it
# prints its welcome and telemetry banner on stdout after the JSON (seen with
# Flutter 3.44). So decode the first JSON array found at a line start and
# ignore whatever surrounds it.
lines = sys.stdin.read().splitlines(True)
devices = []
for i, line in enumerate(lines):
    if line.lstrip().startswith("["):
        try:
            devices, _ = json.JSONDecoder().raw_decode("".join(lines[i:]).lstrip())
            break
        except ValueError:
            continue
for device in devices if isinstance(devices, list) else []:
    kind = "emulator" if device.get("emulator") else "device"
    print("%s (%s, %s %s)" % (device.get("id", "?"), device.get("name", "?"), device.get("targetPlatform", "?"), kind))
')"
  if [ -z "$devices" ]; then
    warn "rig $1: flutter sees no device; boot a simulator or emulator, or attach a device (the drive's HOME is the city, so set ANDROID_HOME in the env_file for Android)"
    return
  fi
  while IFS= read -r line; do
    detail "rig $1: $line"
  done <<LIST
$devices
LIST
}

for_each_rig check
finish "flutter has a device for every rig"
