#!/usr/bin/env bash
set -euo pipefail

# Check exploration_agent/lib for dart:io, but whitelist the dogfood subtree
# (which is private and not exported from lib/exploration_agent.dart).
# See bead lenny-cx6.43.
m=$(grep -rEn "^[[:space:]]*import[[:space:]]+['\"]dart:io['\"]" packages/exploration_agent/lib | grep -v '/lib/src/dogfood/' || true)
if [ -n "$m" ]; then
  echo "ERROR: packages/exploration_agent/lib must not import dart:io (dogfood subtree whitelisted)" >&2
  echo "$m" >&2
  exit 1
fi

# Check exploration_devtools/lib for dart:io
m=$(grep -rEn "^[[:space:]]*import[[:space:]]+['\"]dart:io['\"]" packages/exploration_devtools/lib || true)
if [ -n "$m" ]; then
  echo "ERROR: packages/exploration_devtools/lib must not import dart:io" >&2
  echo "$m" >&2
  exit 1
fi

# Guard: exploration_agent must not import Flutter packages.
# Real imports only — skip lines that are inside block/line comments.
# Pattern matches: package:flutter, package:flutter_test,
#   package:exploration_flutter, dart:ui
FLUTTER_HITS=$(grep -rEn \
  "^[[:space:]]*import[[:space:]]+['\"]((package:(flutter|flutter_test|exploration_flutter))|dart:ui)['\"]" \
  packages/exploration_agent/lib \
  packages/exploration_agent/test \
  || true)
if [ -n "$FLUTTER_HITS" ]; then
  echo "ERROR: exploration_agent must be Flutter-free. Offending imports:" >&2
  echo "$FLUTTER_HITS" >&2
  exit 1
fi
echo "OK: exploration_agent is Flutter-free"

echo "OK: harness + devtools libs are dart:io-free"
