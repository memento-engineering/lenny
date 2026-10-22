#!/usr/bin/env bash
# tool/check_devtools_bundle.sh
#
# Fails when the committed DevTools panel bundle in leonard_flutter differs
# from what tool/build_devtools_extension.sh just built, so a panel change
# cannot merge without its rebuilt bundle (lenny-g7ie4: 0.4.0 through 0.4.1
# shipped a panel built before it learned the acp provider).
#
# Run after the build script. Two outputs change on every build and are
# ignored: flutter_bootstrap.js's serviceWorkerVersion (random per build) and
# .last_build_id.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="packages/leonard_flutter/extension/devtools/build"
cd "$ROOT"

stale=0
git diff --exit-code -I 'serviceWorkerVersion' -- "$BUNDLE" \
  ":(exclude)$BUNDLE/.last_build_id" || stale=1
untracked="$(git ls-files --others --exclude-standard -- "$BUNDLE")"
if [ -n "$untracked" ]; then
  printf 'untracked bundle files:\n%s\n' "$untracked"
  stale=1
fi
if [ "$stale" -ne 0 ]; then
  echo "check_devtools_bundle: $BUNDLE is stale; run ./tool/build_devtools_extension.sh and commit the leonard_flutter copy" >&2
  exit 1
fi
echo "✓ committed DevTools panel bundle matches the build"
