#!/usr/bin/env bash
set -euo pipefail

# Architectural invariants enforced here:
#   1. leonard_agent/lib is dart:io-free (dogfood subtree whitelisted — private,
#      not exported from lib/leonard_agent.dart).
#   2. leonard_devtools/lib is dart:io-free.
#   3. leonard_agent is Flutter-free (no package:flutter*, package:leonard_flutter, dart:ui).
#
# ANTI-ROT: the invariant targets are asserted to exist BEFORE any grep. A grep
# over a missing directory yields no matches, which — combined with `|| true` —
# would make a deleted or renamed target silently PASS, disabling the guard (the
# exact rot this version replaces). Asserting existence makes a future rename fail
# LOUDLY here instead of quietly turning the check into a no-op.

AGENT_LIB="packages/leonard_agent/lib"
AGENT_TEST="packages/leonard_agent/test"
DEVTOOLS_LIB="packages/leonard_devtools/lib"

for d in "$AGENT_LIB" "$AGENT_TEST" "$DEVTOOLS_LIB"; do
  [ -d "$d" ] || { echo "check_no_dart_io: invariant target missing (rename rot?): $d" >&2; exit 1; }
done

# 1. leonard_agent/lib must be dart:io-free (dogfood subtree whitelisted).
m=$(grep -rEn "^[[:space:]]*import[[:space:]]+['\"]dart:io['\"]" "$AGENT_LIB" | grep -v '/lib/src/dogfood/' || true)
if [ -n "$m" ]; then
  echo "ERROR: $AGENT_LIB must not import dart:io (dogfood subtree whitelisted)" >&2
  echo "$m" >&2
  exit 1
fi

# 2. leonard_devtools/lib must be dart:io-free.
m=$(grep -rEn "^[[:space:]]*import[[:space:]]+['\"]dart:io['\"]" "$DEVTOOLS_LIB" || true)
if [ -n "$m" ]; then
  echo "ERROR: $DEVTOOLS_LIB must not import dart:io" >&2
  echo "$m" >&2
  exit 1
fi

# 3. leonard_agent must be Flutter-free (real imports only).
FLUTTER_HITS=$(grep -rEn \
  "^[[:space:]]*import[[:space:]]+['\"]((package:(flutter|flutter_test|leonard_flutter))|dart:ui)['\"]" \
  "$AGENT_LIB" "$AGENT_TEST" \
  || true)
if [ -n "$FLUTTER_HITS" ]; then
  echo "ERROR: leonard_agent must be Flutter-free. Offending imports:" >&2
  echo "$FLUTTER_HITS" >&2
  exit 1
fi

echo "OK: leonard_agent is Flutter-free; leonard_agent + leonard_devtools libs are dart:io-free"
