#!/usr/bin/env bash
set -euo pipefail
m=$(grep -rEn "^[[:space:]]*import[[:space:]]+['\"]dart:io['\"]" \
  packages/exploration_agent/lib || true)
if [ -n "$m" ]; then
  echo "ERROR: exploration_agent/lib must not import dart:io" >&2
  echo "$m" >&2; exit 1
fi
echo "OK: exploration_agent/lib is dart:io-free"
