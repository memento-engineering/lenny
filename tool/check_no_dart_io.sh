#!/usr/bin/env bash
set -euo pipefail
for t in packages/exploration_agent/lib packages/exploration_devtools/lib; do
  m=$(grep -rEn "^[[:space:]]*import[[:space:]]+['\"]dart:io['\"]" "$t" || true)
  if [ -n "$m" ]; then
    echo "ERROR: $t must not import dart:io" >&2
    echo "$m" >&2
    exit 1
  fi
done
echo "OK: harness + devtools libs are dart:io-free"
