#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

# Only runs that set leonard.device and leonard.target build and launch the
# app; a vm_uri run attaches to an app that is already running and needs
# none of these tools. So a missing tool is a warning, not an error.

check() {
  # check <rig> <leonard_cli> <env_file>
  local tool found="" path
  if ! env_file_loads "$3" >/dev/null; then
    fail "rig $1: cannot look for tools, its env_file does not load (see leonard:env-file)"
    return
  fi
  if path="$(in_check_env "$3" command -v flutter 2>/dev/null)"; then
    detail "rig $1: flutter $path"
  else
    warn "rig $1: flutter is not on the drive's PATH; device/target runs need it (add Flutter's bin to PATH in the env_file)"
  fi
  for tool in xcodebuild adb; do
    if path="$(in_check_env "$3" command -v "$tool" 2>/dev/null)"; then
      found="$found $tool"
      detail "rig $1: $tool $path"
    fi
  done
  case "$found" in
    *xcodebuild*)
      in_check_env "$3" perl -e "$TIMEOUT_PL" 30 xcodebuild -version >/dev/null 2>&1 ||
        warn "rig $1: xcodebuild is present but no Xcode is selected (sudo xcode-select -s /Applications/Xcode.app)"
      ;;
  esac
  [ -n "$found" ] ||
    warn "rig $1: neither Xcode (xcodebuild) nor the Android SDK (adb) is on the drive's PATH; device/target runs cannot build for iOS, macOS or Android"
}

for_each_rig check
finish "platform tools found for every rig"
